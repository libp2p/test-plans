#!/usr/bin/env python

import toml
import jinja2
import json
import argparse
import os
import pathlib
import subprocess
import time
import analyze
import re

TESTGROUND_BIN = 'testground'

DEFAULT_GS_VERSION = 'latest'

# setting this build tag lets us compile test code that targets the new API from the hardening branch
HARDENED_API_BUILD_TAG = 'hardened_api'

# Testground build/run config settings to use when running on kubernetes
K8S_BUILD_CONFIG = {'bypass_cache': True, 'push_registry': True, 'registry_type': 'aws'}
K8S_RUN_CONFIG = {}

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('param_files', nargs='*',
                        help='name of one or more parameter files to use when generating composition from template. ' +
                             'if a param is defined in multiple files, last one wins.')

    parser.add_argument('--name',
                        help='name of composition. will be used to create output directory.')

    parser.add_argument('--template_dir',
                        default='./templates/baseline',
                        help='path to directory containing composition template and param files')

    parser.add_argument('-o', '--output',
                        help='directory to write composition file and test outputs to',
                        default='./output')

    parser.add_argument('--branch',
                        default='master',
                        help='configures the test to use the API from the given gossipsub branch')

    parser.add_argument('--commit',
                        help='configures the test to use the API from the given gossipsub commit')

    parser.add_argument('--k8s', action='store_true', default=False,
                        help='runs the test on kubernetes')

    parser.add_argument('--dry-run', dest='dry_run', action='store_true', default=False,
                        help='skip running tests, just write composition files and exit')

    parser.add_argument('--instances', type=int,
                        help='override the total number of test instances. equivalent to -D N_NODES=x')

    parser.add_argument('-D', '--define', dest='definitions', action='append',
                        metavar='<key=value>',
                        help='set template variable `key` to `value`, e.g. -D T_RUN=10m')

    parser.add_argument('--skip-analysis', dest='skip_analysis', action='store_true', default=False,
                        help='skip analysis phase after test run (can run manually later with analyze.py)')

    return parser.parse_args()


def get_param_filepath(template_dir, param_filename):
    p = param_filename
    if os.path.exists(p):
        return p

    p = os.path.join(template_dir, 'params', p)
    if os.path.exists(p):
        return p

    p = param_filename + '.toml'
    if os.path.exists(p):
        return p

    p = os.path.join(template_dir, 'params', p)
    if os.path.exists(p):
        return p

    raise ValueError("can't find param file " + param_filename)


def load_params(template_dir, param_files):
    base_params_path = os.path.join(template_dir, 'params', '_base.toml')
    paths = [get_param_filepath(template_dir, p) for p in param_files]

    params = dict()
    for path in [base_params_path] + paths:
        p = toml.load(path)
        for k, v in p.items():
            params[k] = v

    return params


# N_ATTACK_NODES can either be
# - a number
# - a string of the form "5@10s,10@1m,20@2m"
def parse_n_attack_nodes(params):
    attack_nodes_param = params['N_ATTACK_NODES']
    if attack_nodes_param is None:
        return
    if isinstance(attack_nodes_param, int) or isinstance(attack_nodes_param, float):
        return
    if attack_nodes_param.isdigit():
        return

    num_durations = attack_nodes_param.split(',')
    n_nodes = 0
    for num_duration in num_durations:
        try:
            num, duration = num_duration.split('@')
            n_nodes += int(num)
        except:
            raise ValueError("Badly formatted N_ATTACK_NODES: " + attack_nodes_param)

    params['N_ATTACK_NODES'] = n_nodes
    params['ATTACKER_CONNECT_DELAYS'] = attack_nodes_param


# The TOPOLOGY parameter can be either
# - a JSON representation of a topology
# - a path to a file in that format
def parse_topology(params):
    if 'TOPOLOGY' not in params:
        params['TOPOLOGY'] = None
        return

    # If it's already JSON, we're all set
    top = params['TOPOLOGY']
    if len(top) > 0 and top[0] == '{':
        return

    # It's not JSON so assume it's a file path
    if not os.path.exists(top):
        raise ValueError("can't find topology file " + top)

    # Make sure the file contents is JSON
    with open(top, 'r') as infile:
        contents = infile.read()
        jsonstr = json.loads(contents)
        params['TOPOLOGY'] = jsonstr


# N_CONTAINER_NODES_TOTAL is the total number of nodes including multiple nodes
# per container
def parse_n_container_nodes_total(params):
    n_nodes = params.get('N_NODES', 20)
    n_attack_nodes = params.get('N_ATTACK_NODES', 0)
    n_nodes_cont_honest = params.get('N_HONEST_PEERS_PER_NODE', 1)
    n_nodes_cont_attack = params.get('N_ATTACK_PEERS_PER_NODE', 1)

    n_honest_nodes = n_nodes - n_attack_nodes
    total = n_honest_nodes * n_nodes_cont_honest + n_attack_nodes * n_nodes_cont_attack
    params['N_CONTAINER_NODES_TOTAL'] = total


def render_template(template_dir, params):
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(template_dir)
    )

    template = env.get_template('template.toml.j2')
    return template.render(**params)


def composition_name():
    ts = time.strftime("%Y%m%d-%H%M%S")
    return 'pubsub-test-{}'.format(ts)


def mkdirp(dirpath):
    pathlib.Path(dirpath).mkdir(parents=True, exist_ok=True)


def run_composition(comp_filepath, output_dir, k8s=False):
    archive_type = 'tgz' if k8s else 'zip'
    outfilename = 'test-output.{}'.format(archive_type)
    outpath = os.path.join(output_dir, outfilename)

    print('running testground composition {}'.format(comp_filepath))
    print("writing test outputs to {}".format(output_dir))
    cmd = [TESTGROUND_BIN, 'run', 'composition', '-f', comp_filepath, '--collect', '-o', outpath]
    subprocess.run(cmd, check=True)

    print('test completed successfully!')
    return outpath


def pubsub_commit(ref_str):
    # if the input looks like a git commit already, just return it as-is
    if re.match(r'\b([a-f0-9]{40})\b', ref_str):
        return ref_str

    out = subprocess.run(['git', 'ls-remote', 'git://github.com/libp2p/go-libp2p-pubsub'],
                         check=True, capture_output=True, text=True)

    # look for matching branch or tag in output
    pattern = r'^\b([a-f0-9]{40})\b.*refs/(heads|tags)/' + ref_str + '$'
    m = re.search(pattern, out.stdout, re.MULTILINE)
    if not m:
        raise ValueError('no branch or tag found matching {}'.format(ref_str))
    return m.group(1)


def run():
    args = parse_args()
    template_dir = args.template_dir

    params = load_params(template_dir, args.param_files)

    branch = None
    if args.branch:
        branch = args.branch
        params['GS_VERSION'] = pubsub_commit(args.branch)
    if args.commit:
        params['GS_VERSION'] = args.commit
    if branch is None and args.commit is None:
        params['GS_VERSION'] = 'latest'


    gs_version_msg = 'Using go-libp2p-pubsub commit ' + params['GS_VERSION']
    if branch:
        gs_version_msg += ' (' + branch + ')'
    print(gs_version_msg)

    if args.k8s:
        params['TEST_RUNNER'] = 'cluster:k8s'
        params['BUILD_CONFIG'] = toml.dumps(K8S_BUILD_CONFIG)
        params['RUN_CONFIG'] = toml.dumps(K8S_RUN_CONFIG)

    if args.instances is not None:
        params['N_NODES'] = args.instances

    if args.definitions is not None:
        for defstr in args.definitions:
            [k, v] = defstr.split('=')
            try:
                v = float(v)
                if v.is_integer():
                    v = int(v)
                params[k] = v
            except:
                params[k] = v

    parse_topology(params)
    parse_n_attack_nodes(params)
    parse_n_container_nodes_total(params)

    comp = composition_name()
    if args.name:
        comp += '-' + args.name

    workdir = os.path.join(args.output, comp)
    pathlib.Path(workdir).mkdir(parents=True, exist_ok=True)

    comp_filepath = os.path.join(workdir, 'composition.toml')
    with open(comp_filepath, 'w', encoding='utf8') as f:
        f.write(render_template(template_dir, params))

    param_filepath = os.path.join(workdir, 'template-params.toml')
    with open(param_filepath, 'wt') as f:
        toml.dump(params, f)

    print('wrote composition file to {}'.format(comp_filepath))

    if args.dry_run:
        print('dry run. skipping test execution')
        return

    test_output_archive = run_composition(comp_filepath, workdir, args.k8s)
    if not args.skip_analysis:
        print('extracting test output data')
        analyze.extract_test_outputs(test_output_archive)


if __name__ == "__main__":
    run()

