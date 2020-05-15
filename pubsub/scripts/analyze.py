#!/usr/bin/env python

import argparse
import os
import zipfile
import gzip
import tarfile
import contextlib
import tempfile
import json
import subprocess
import pathlib
import pandas as pd
from glob import glob
import multiprocessing as mp
import shutil
import re
import sys



ANALYSIS_NOTEBOOK_TEMPLATE = 'Analysis-Template.ipynb'

def mkdirp(dirpath):
    pathlib.Path(dirpath).mkdir(parents=True, exist_ok=True)


def parse_args():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers()
    extract_cmd = commands.add_parser('extract', help='extract test outputs from testground output archive')
    extract_cmd.add_argument('test_output_zip_path', nargs=1,
                        help='path to testground output zip or tgz file')

    extract_cmd.add_argument('--output-dir', '-o', dest='output_dir', default=None,
                             help='path to write output files. default is to create a new dir based on zip filename')
    extract_cmd.set_defaults(subcomment='extract')

    run_notebook_cmd = commands.add_parser('run_notebook',
                                           help='runs latest analysis notebook against extracted test data')
    run_notebook_cmd.add_argument('test_result_dir', nargs='+',
                                  help='directories to run against. must contain an "analysis" subdir with extracted test data')
    run_notebook_cmd.set_defaults(subcommand='run_notebook')
    return parser.parse_args()


def concat_files(names, outfile):
    for name in names:
        with open(name, 'rb') as f:
            outfile.write(f.read())


# depending on which test runner was used, the collection archive may be either a zip (local docker & exec runner),
# or a tar.gz file (k8s). Unfortunately, the zipfile and tarfile modules are different species of waterfowl,
# so we duck typing doesn't help. So this method extracts whichever one we have to a temp directory and
# returns the path to the temp dir.
# use as a context manager, so the temp dir gets deleted when we're done:
#   with open_archive(archive_path) as a:
#     files = glob(a + '/**/tracer-output')
@contextlib.contextmanager
def open_archive(archive_path):
    # zipfile and tarfile both have an extractall method, at least
    if zipfile.is_zipfile(archive_path):
        z = zipfile.ZipFile(archive_path)
    else:
        z = tarfile.open(archive_path, 'r:gz')

    with tempfile.TemporaryDirectory(prefix='pubsub-tg-archive-') as d:
        z.extractall(path=d)
        yield d


# sugar around recursive glob search
def find_files(dirname, filename_glob):
    path = '{}/**/{}'.format(dirname, filename_glob)
    return glob(path, recursive=True)


PEER_INFO_PATTERN = re.compile(r'Host peer ID: ([0-9a-zA-Z]+), seq (\d+), node type: ([a-z]+), node type seq: (\d+), node index: (\d+) / (\d+)')
def extract_peer_info(run_out):
    with open(run_out, 'rt') as f:
        for line in f.readlines():
            m = PEER_INFO_PATTERN.search(line)
            if m:
                pid = m.group(1)
                seq = int(m.group(2))
                node_type = m.group(3)
                node_type_seq = int(m.group(4))
                node_index = int(m.group(5))
                node_index_bound = int(m.group(6))
                return {'peer_id': pid,
                        'type': node_type,
                        'seq': seq,
                        'node_type_seq': node_type_seq,
                        'node_index': node_index,
                        'node_index_bound': node_index_bound}
    print('warning: no peer info found in {}'.format(run_out))
    return None


def extract_timing_info(run_out, node_type):
    if node_type == 'honest':
        times = dict(t_warm=0, t_connect=0, t_run=0, t_cool=0, t_complete=0)
    else:
        times = dict(t_connect=0)

    with open(run_out, 'rt') as f:
        for line in f.readlines():
            try:
                obj = json.loads(line)
            except BaseException as err:
                print("error parsing run output: ", err)
                continue
            if 'ts' not in obj or 'event' not in obj or obj['event'].get('type', '') != 'message':
                continue
            msg = obj['event']['message']
            ts = obj['ts']
            if re.match(r'connecting to peers.*', msg):
                times['t_connect'] = ts
                continue

            # the rest of the times are only logged by honest peers
            if node_type != 'honest':
                continue
            if re.match(r'Wait for .* warmup time', msg):
                times['t_warm'] = ts
                continue
            if re.match(r'Wait for .* run time', msg):
                times['t_run'] = ts
                continue
            if re.match(r'Run time complete, cooling down.*', msg):
                times['t_cool'] = ts
                continue
            if msg == 'Cool down complete':
                times['t_complete'] = ts
                continue

    for k, v in times.items():
        if v == 0:
            print('warning: unable to determine time value for {}'.format(k))
    return times


def extract_peer_and_timing_info(run_out_files):
    entries = []
    for filename in run_out_files:
        info = extract_peer_info(filename)
        if info is None:
            continue
        times = extract_timing_info(filename, info.get('type', 'unknown'))
        info.update(times)
        entries.append(info)
    return entries


def aggregate_output(output_zip_path, out_dir):
    topology = dict()

    with open_archive(output_zip_path) as archive:
        tracefiles = find_files(archive, 'tracer-output*')
        names = [f for f in tracefiles if 'full' in f]
        if len(names) > 0:
            with gzip.open(os.path.join(out_dir, 'full-trace.bin.gz'), 'wb') as gz:
                concat_files(names, gz)

        names = [f for f in tracefiles if 'filtered' in f]
        if len(names) > 0:
            with gzip.open(os.path.join(out_dir, 'filtered-trace.bin.gz'), 'wb') as gz:
                concat_files(names, gz)

        # copy aggregate metrics files
        names = [f for f in tracefiles if 'aggregate' in f]
        for name in names:
            dest = os.path.join(out_dir, os.path.basename(name))
            shutil.copyfile(name, dest)

        # copy peer score files
        names = find_files(archive, 'peer-scores*')
        for name in names:
            dest = os.path.join(out_dir, os.path.basename(name))
            shutil.copyfile(name, dest)

        # get peer id -> seq mapping & timing info from run.out files
        names = find_files(archive, 'run.out')
        info = extract_peer_and_timing_info(names)
        dest = os.path.join(out_dir, 'peer-info.json')
        with open(dest, 'wt') as f:
            json.dump(info, f)

        # Collect contents of all files of the form 'connections-honest-8-1'
        names = find_files(archive, 'connections*')
        for name in names:
            with open(name, 'r') as infile:
                name = os.path.basename(name)
                _, node_type, node_type_seq, node_idx = name.split('.')[0].split('-')
                conns = json.loads(infile.read())
                topology[node_type + '-' + node_type_seq + '-' + node_idx] = conns or []

    # Write out topology file
    top_path = os.path.join(out_dir, 'topology.json')
    with open(top_path, 'wt') as outfile:
        outfile.write(json.dumps(topology))


def run_tracestat(tracer_output_dir):
    full = os.path.join(tracer_output_dir, 'full-trace.bin.gz')
    filtered = os.path.join(tracer_output_dir, 'filtered-trace.bin.gz')
    if os.path.exists(full):
        tracer_output = full
    elif os.path.exists(filtered):
        tracer_output = filtered
    else:
        print('no event tracer output found, skipping tracestat')
        return

    print('running tracestat on {}'.format(tracer_output))
    try:
        cmd = ['go', 'run', 'github.com/libp2p/go-libp2p-pubsub-tracer/cmd/tracestat', '-cdf', tracer_output]
        p = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except BaseException as err:
        print('error calling tracestat: ', err)
        return

    # split output into summary and latency CDF
    [summary, cdf] = p.stdout.split('=== Propagation Delay CDF (ms) ===')

    with open(os.path.join(tracer_output_dir, 'tracestat-summary.txt'), 'w', encoding='utf8') as f:
        f.write(summary)
    with open(os.path.join(tracer_output_dir, 'tracestat-cdf.txt'), 'w', encoding='utf8') as f:
        f.write(cdf)

    print(summary)


def extract_test_outputs(test_output_zip_path, output_dir=None, convert_to_pandas=False, prep_notebook=True):
    if output_dir is None or output_dir == '':
        output_dir = os.path.join(os.path.dirname(test_output_zip_path), 'analysis')

    mkdirp(output_dir)
    aggregate_output(test_output_zip_path, output_dir)
    run_tracestat(output_dir)

    if convert_to_pandas:
        import notebook_helper
        print('converting data to pandas format...')
        notebook_helper.to_pandas(output_dir, os.path.join(output_dir, 'pandas'))
    if prep_notebook:
        prepare_analysis_notebook(analysis_dir=output_dir)
    return output_dir


def prepare_analysis_notebook(analysis_dir):
    notebook_out = os.path.join(analysis_dir, 'Analysis.ipynb')
    shutil.copy(ANALYSIS_NOTEBOOK_TEMPLATE, notebook_out)
    shutil.copy('./notebook_helper.py', os.path.join(analysis_dir, 'notebook_helper.py'))
    print('saved analysis notebook to {}'.format(notebook_out))


def run_analysis_notebook(analysis_dir):
    prepare_analysis_notebook(analysis_dir)
    notebook_path = os.path.join(analysis_dir, 'Analysis.ipynb')
    cmd = ['papermill', ANALYSIS_NOTEBOOK_TEMPLATE, notebook_path, '--cwd', analysis_dir]
    try:
        subprocess.run(cmd, check=True)
    except BaseException as err:
        print('error executing notebook: {}'.format(err), file=sys.stderr)
        return


def run_notebooks(test_result_dirs):
    for d in test_result_dirs:
        analysis_dir = os.path.join(d, 'analysis')
        if not os.path.exists(analysis_dir):
            print('no analysis dir at {}, ignoring'.format(analysis_dir), file=sys.stderr)
            continue
        print('running analysis in {}'.format(analysis_dir))
        run_analysis_notebook(analysis_dir)


def run():
    args = parse_args()
    if args.subcommand == 'extract':
        zip_filename = args.test_output_zip_path[0]
        extract_test_outputs(zip_filename, args.output_dir)
    elif args.subcommand == 'run_notebook':
        run_notebooks(args.test_result_dir)
    else:
        print('unknown subcommand', file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    run()
