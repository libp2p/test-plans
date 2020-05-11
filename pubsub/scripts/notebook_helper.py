import os
import json
import pathlib
import multiprocessing as mp
from glob import glob
import pandas as pd
import toml
import ipywidgets as widgets
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import matplotlib.patches as mpatches
import seaborn as sns
import numpy as np
import zipfile


def mkdirp(dirpath):
    pathlib.Path(dirpath).mkdir(parents=True, exist_ok=True)

# sugar around recursive glob search
def find_files(dirname, filename_glob):
    path = '{}/**/{}'.format(dirname, filename_glob)
    return glob(path, recursive=True)

def empty_scores_dataframe():
    return pd.DataFrame([], columns=['observer', 'peer', 'timestamp', 'score']).astype(
        {'score': 'float64', 'observer': 'int64', 'peer': 'int64', 'timestamp': 'datetime64[ns]'})


def aggregate_peer_scores_single(scores_filepath, peers_table):
    df = empty_scores_dataframe()

    # select the cols from peers table we want to join on
    p = peers_table[['peer_id', 'seq', 'honest']]

    with open(scores_filepath, 'rt') as f:
        for line in iter(f.readline, ''):
            try:
                data = json.loads(line)
            except BaseException as err:
                print('error parsing score json: ', err)
                continue
            scores = pd.json_normalize(data['Scores'])
            scores = scores.T \
                .rename(columns={0: 'score'}) \
                .reset_index() \
                .rename(columns={'index': 'peer_id'})
            scores['timestamp'] = pd.to_datetime(data['Timestamp'])
            scores['observer_id'] = data['PeerID']

            # join with peers table to convert peer ids to seq numbers
            s = scores.merge(p, on='peer_id').drop(columns=['peer_id'])
            s = s.merge(p.drop(columns=['honest']), left_on='observer_id', right_on='peer_id', suffixes=['_peer', '_observer'])
            s = s.drop(columns=['peer_id', 'observer_id'])
            s = s.rename(columns={'seq_peer': 'peer', 'seq_observer': 'observer'})

            df = df.append(s, ignore_index=True)
    df.set_index('timestamp', inplace=True)
    return df


def aggregate_peer_scores(score_filepaths, peers_table):
    if len(score_filepaths) == 0:
        return empty_scores_dataframe()
    pool = mp.Pool(mp.cpu_count())
    args = [(f, peers_table) for f in score_filepaths]
    results = pool.starmap(aggregate_peer_scores_single, args)
    # concat all data frames into one
    return pd.concat(results)


def empty_metrics_dataframe():
    return pd.DataFrame([], columns=['published', 'rejected', 'delivered', 'duplicates', 'droppedrpc',
                                     'peersadded', 'peersremoved', 'topicsjoined', 'topicsleft', 'peer',
                                     'sent_rpcs', 'sent_messages', 'sent_grafts', 'sent_prunes',
                                     'sent_iwants', 'sent_ihaves', 'recv_rpcs', 'recv_messages',
                                     'recv_grafts', 'recv_prunes', 'recv_iwants', 'recv_ihaves'])


def aggregate_metrics_to_pandas_single(metrics_filepath, peers_table):
    def munge_keys(d, prefix=''):
        out = dict()
        for k, v in d.items():
            outkey = prefix + k.lower()
            out[outkey] = v
        return out


    rows = list()
    with open(metrics_filepath, 'rb') as f:
        try:
            e = json.load(f)
        except BaseException as err:
            print('error loading metrics entry: ', err)
        else:
            pid = e['LocalPeer']
            sent = munge_keys(e['SentRPC'], 'sent_')
            recv = munge_keys(e['ReceivedRPC'], 'recv_')
            del(e['LocalPeer'], e['SentRPC'], e['ReceivedRPC'])
            row = munge_keys(e)
            row.update(sent)
            row.update(recv)
            rows.append(row)
            row['peer_id'] = pid

    df = pd.DataFrame(rows)
    p = peers_table[['peer_id', 'seq']]
    df = df.merge(p, on='peer_id').drop(columns=['peer_id']).rename(columns={'seq': 'peer'})
    return df.astype('int64')


def aggregate_metrics_to_pandas(metrics_filepaths, peers_table):
    if len(metrics_filepaths) == 0:
        return empty_metrics_dataframe()
    pool = mp.Pool(mp.cpu_count())
    args = [(f, peers_table) for f in metrics_filepaths]
    results = pool.starmap(aggregate_metrics_to_pandas_single, args)
    # concat all data frames into one
    return pd.concat(results)


def cdf_to_pandas(cdf_filepath):
    if os.path.exists(cdf_filepath):
        return pd.read_csv(cdf_filepath, delim_whitespace=True, names=['delay_ms', 'count'], dtype='int64')
    else:
        return pd.DataFrame([], columns=['delay_ms', 'count'], dtype='int64')


def peer_info_to_pandas(peer_info_filename):
    with open(peer_info_filename, 'rt') as f:
        data = json.load(f)
    peers = pd.json_normalize(data)
    peers['honest'] = peers['type'] == 'honest'
    return peers.astype({'type': 'category',
                         't_warm': 'datetime64[ns]',
                         't_connect': 'datetime64[ns]',
                         't_run': 'datetime64[ns]',
                         't_cool': 'datetime64[ns]',
                         't_complete': 'datetime64[ns]'})


def to_pandas(aggregate_output_dir, pandas_output_dir):
    mkdirp(pandas_output_dir)

    print('converting peer ids and info to pandas...')
    peer_info_filename = os.path.join(aggregate_output_dir, 'peer-info.json')
    peers = peer_info_to_pandas(peer_info_filename)
    outfile = os.path.join(pandas_output_dir, 'peers.gz')
    peers.to_pickle(outfile)

    print('converting peer scores to pandas...')
    scores_files = find_files(aggregate_output_dir, 'peer-scores*')
    df = aggregate_peer_scores(scores_files, peers)
    outfile = os.path.join(pandas_output_dir, 'scores.gz')
    print('writing pandas peer scores to {}'.format(outfile))
    df.to_pickle(outfile)

    print('converting aggregate metrics to pandas...')
    outfile = os.path.join(pandas_output_dir, 'metrics.gz')
    metrics_files = find_files(aggregate_output_dir, '*aggregate.json')
    df = aggregate_metrics_to_pandas(metrics_files, peers)
    print('writing aggregate metrics pandas data to {}'.format(outfile))
    df.to_pickle(outfile)

    print('converting latency cdf to pandas...')
    outfile = os.path.join(pandas_output_dir, 'cdf.gz')
    cdf_file = os.path.join(aggregate_output_dir, 'tracestat-cdf.txt')
    df = cdf_to_pandas(cdf_file)
    print('writing cdf pandas data to {}'.format(outfile))
    df.to_pickle(outfile)


def write_pandas(tables, output_dir):
    pandas_dir = os.path.join(output_dir, 'pandas')
    mkdirp(pandas_dir)
    for name, df in tables.items():
        fname = os.path.join(pandas_dir, '{}.gz'.format(name))
        df.to_pickle(fname)


def load_pandas(analysis_dir):
    analysis_dir = os.path.abspath(analysis_dir)
    pandas_dir = os.path.join(analysis_dir, 'pandas')
    if not os.path.exists(pandas_dir):
        print('Cached pandas data not found. Converting analysis data from {} to pandas'.format(analysis_dir))
        to_pandas(analysis_dir, pandas_dir)

    tables = {}
    for f in os.listdir(pandas_dir):
        if not f.endswith('.gz'):
            continue
        name = os.path.splitext(f)[0]
        tables[name] = pd.read_pickle(os.path.join(pandas_dir, f))

    if 'cdf' in tables:
        tables['pdf'] = cdf_to_pdf(tables['cdf'])

    return tables


def test_params_panel(analysis_dir):
    param_filename = os.path.join(analysis_dir, '..', 'template-params.toml')
    with open(param_filename, 'rt') as f:
        contents = f.read()
        test_params = toml.loads(contents)

    params_out = widgets.Output()
    with params_out:
        print(contents)

    params_panel = widgets.Accordion([params_out])
    params_panel.set_title(0, 'Test Parameters')
    params_panel.selected_index = None
    return (params_panel, test_params)


def save_fig_fn(dest, formats=['png', 'pdf']):
    mkdirp(dest)

    def save_fig(fig, filename, **kwargs):
        try:
            for fmt in formats:
                base = os.path.splitext(filename)[0]
                name = os.path.join(dest, '{}.{}'.format(base, fmt))
                fig.savefig(name, format=fmt, **kwargs)
        except BaseException as err:
            print('Error saving figure to {}: {}'.format(filename, err))
    return save_fig


def zipdir(path, ziph, extensions=['.png', '.pdf', '.eps', '.svg']):
    # ziph is zipfile handle
    for root, dirs, files in os.walk(path):
        for file in files:
            strs = os.path.splitext(file)
            if len(strs) < 2:
                continue
            ext = strs[1]
            if ext not in extensions:
                continue
            ziph.write(os.path.join(root, file))


def archive_figures(figure_dir, out_filename):
    zipf = zipfile.ZipFile(out_filename, 'w', zipfile.ZIP_DEFLATED)
    zipdir(figure_dir, zipf)
    zipf.close()


def no_scores_message():
    from IPython.display import display, Markdown
    display(Markdown("""##### No peer score data, chart omitted"""))


def tracestat_summary(analysis_dir):
    summary_file = os.path.join(analysis_dir, 'tracestat-summary.txt')
    if os.path.exists(summary_file):
        with open(summary_file, 'rt') as f:
            return f.read()
    else:
        return('no tracestat summary file found')


def make_line(label, ax, x, color, alpha=0.5, linestyle='dashed'):
    ax.axvline(x=x, linestyle=linestyle, color=color, alpha=alpha)
    return mlines.Line2D([], [], color=color, linestyle=linestyle, label=label, alpha=alpha)


def make_span(label, ax, start, end, color, alpha=0.3):
    ax.axvspan(start, end, facecolor=color, alpha=alpha)
    return mpatches.Patch(color=color, alpha=alpha, label=label)


def annotate_times(ax, time_annotations, legend_anchor=None):
    colors = sns.color_palette('Set2')
    def next_color():
        c = colors.pop(0)
        colors.append(c)
        return c

    legends = []
    for a in time_annotations:
        t1 = a['time']
        if pd.isnull(t1):
            continue
        label = a['label']
        if 'end_time' in a:
            # if we have an end_time, draw a span between start and end
            t2 = a['end_time']
            if pd.isnull(t2):
                continue
            legends.append(make_span(label, ax, t1, t2, next_color()))
        else:
            # otherwise, draw a dashed line at t1
            legends.append(make_line(label, ax, t1, next_color()))

    if len(legends) != 0 and legend_anchor is not None:
        # add the original legend to the plot
        ax.add_artist(ax.legend(loc='upper left'))
        # add second legend for marker lines
        ax.legend(handles=legends, bbox_to_anchor=legend_anchor, loc='upper left')


def annotate_score_plot(plot, title, legend_anchor=None, time_annotations=[]):
    plot.set_title(title)
    plot.set_ylabel('score')
    plot.set_xlabel('')
    if len(time_annotations) != 0:
        annotate_times(plot, time_annotations, legend_anchor=legend_anchor)


def draw_latency_threshold_lines(max_val, eth_threshold=3000, fil_threshold=6000):
    legends = []
    if max_val > eth_threshold * 0.75:
        plt.axvline(eth_threshold, linestyle='--', color='orange')
        l = mlines.Line2D([], [], color='orange', linestyle='--', label='Eth2 threshold')
        legends.append(l)

    if max_val > fil_threshold * 0.75:
        plt.axvline(fil_threshold, linestyle='--', color='blue')
        l = mlines.Line2D([], [], color='blue', linestyle='--', label='Fil threshold')
        legends.append(l)

    if len(legends) > 0:
        plt.legend(handles=legends)


def plot_latency_cdf(cdf):
    fig = plt.figure(figsize=(11,6))
    fig.suptitle("Latency CDF")
    plt.plot('delay_ms', 'count', data=cdf)
    plt.ylabel('messages')
    plt.xlabel('ms to fully propagate')
    draw_latency_threshold_lines(cdf['delay_ms'].max())
    plt.show()
    return fig


def plot_latency_pdf(pdf):
    fig = plt.figure(figsize=(11,6))
    fig.suptitle('Latency Distribution (PDF)')
    plt.hist(pdf['delay_ms'], weights=pdf['count'], bins=50)
    plt.ylabel('messages')
    plt.xlabel('ms to fully propagate')
    draw_latency_threshold_lines(pdf['delay_ms'].max())
    plt.show()
    return fig


def plot_latency_pdf_above_quantile(pdf, quantile=0.99):
    delays = pdf.reindex(pdf.index.repeat(pdf['count']))
    q = delays['delay_ms'].quantile(quantile)

    fig = plt.figure(figsize=(11,6))
    qname = 'p{}'.format(int(round(quantile, 2) * 100))
    fig.suptitle('Latency PDF above {} ({:.2f}ms)'.format(qname, round(q, 2)))
    delays['delay_ms'].where(delays['delay_ms'] > q).dropna().plot.hist(bins=50)
    plt.ylabel('messages')
    plt.xlabel('ms to fully propagate')
    plt.show()
    return fig


def cdf_to_pdf(cdf):
    delta = [0] * len(cdf['count'])
    delta[0] = cdf['count'][0]
    for x in range(1, len(cdf['count'])):
        delta[x] = cdf['count'][x] - cdf['count'][x-1]
    return pd.DataFrame({'delay_ms': cdf['delay_ms'], 'count': delta})


def p25(x):
    return np.percentile(x, q=25)


def p50(x):
    return np.percentile(x, q=50)


def p75(x):
    return np.percentile(x, q=75)


def p95(x):
    return np.percentile(x, q=95)


def p99(x):
    return np.percentile(x, q=99)