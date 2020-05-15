import ipywidgets as widgets
import run as run_helpers
from bunch import Bunch
import functools
import operator
import stringcase
import subprocess
import os
import toml
import json
import time
from jupyter_ui_poll import ui_events
from IPython.display import display
import analyze
import shutil

# TODO: move constants
TEMPLATE = 'templates/baseline'

# set to path of testground bin if not in PATH
TESTGROUND = 'testground'


class RunButton(object):
    def __init__(self, config):
        self.config = config
        self.pressed = False
        self.button = widgets.Button(description='Run Test', button_style='primary')
        self.button.on_click(self._clicked)

    def _clicked(self, evt):
        self.pressed = True
        self.button.description = 'Running'
        self.button.button_style = 'info'
        self.button.disabled = True

    def wait(self):
        display(self.button)
        with ui_events() as poll:
            while self.pressed is False:
                poll(10)                # React to UI events (upto 10 at a time)
                time.sleep(0.1)
        self._run()

    def _run(self):
        endpoint = self.config.widgets.testground.daemon_endpoint.value
        workdir = self.config.widgets.test_execution.output_dir.value
        failed_dir = self.config.widgets.test_execution.failed_dir.value
        run_helpers.mkdirp(workdir)
        run_helpers.mkdirp(failed_dir)

        params = self.config.template_params()
        comp = self.config.composition()
        comp_filename = os.path.join(workdir, 'composition.toml')
        params_filename = os.path.join(workdir, 'template-params.toml')
        config_snapshot_filename = os.path.join(workdir, 'config-snapshot.json')

        if 'k8s' in params['TEST_RUNNER']:
            archive_filename = os.path.join(workdir, 'test-output.tgz')
        else:
            archive_filename = os.path.join(workdir, 'test-output.zip')

        with open(comp_filename, 'wt') as f:
            f.write(comp)

        with open(params_filename, 'w') as f:
            toml.dump(params, f)

        with open(config_snapshot_filename, 'w') as f:
            json.dump(self.config.snapshot(), f)

        cmd = [TESTGROUND, '--vv',
               '--endpoint', endpoint,
               'run', 'composition',
               '-f', comp_filename,
               '--collect', '-o', archive_filename]

        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        for line in iter(p.stdout.readline, ''):
            print(line, end='')
            if p.poll():
                break
        self.button.description = 'Done'
        self.button.button_style = 'danger'
        return_code = p.wait()
        if return_code:
            try:
                shutil.move(workdir, failed_dir)
            except BaseException as err:
                print('tried to move output from failed test to {}, but failed with error: {}'.format(failed_dir, err))
            raise ValueError('test execution failed, skipping analysis. moved outputs to {}'.format(failed_dir))

        print('test outputs saved to {}'.format(workdir))
        print('extracting test data for analysis...')
        analysis_dir = os.path.join(workdir, 'analysis')
        analyze.extract_test_outputs(archive_filename, analysis_dir, convert_to_pandas=False, prep_notebook=True)
        print('saved analysis outputs to {}'.format(analysis_dir))




# a collapsible panel for a single topic's params
class TopicConfigPanel(object):
    def __init__(self):
        self.topic_widgets = Bunch(
            name=widgets.Text(description="Topic Name", value="blocks"),
            message_rate=widgets.Text(description="Message Rate (msg/sec)", value='120/s'),
            message_size=widgets.Text(description="Message Size", value="2 KiB"),
        )

        self.topic_weight = widgets.FloatText(description="Topic Weight", value=0.25)

        # NOTE: don't change the description values! they're used to derive the JSON keys when
        # collecting the param values later
        self.score_widgets = Bunch(
            time_in_mesh=Bunch(
                weight=widgets.FloatText(description="Time in Mesh Weight", value=0.0027),
                quantum=widgets.Text(description="Time in Mesh Quantum", value='1s'),
                cap=widgets.FloatText(description="Time in Mesh Cap", value=3600)
            ),
            first_message_deliveries=Bunch(
                weight=widgets.FloatText(description="First Message Deliveries Weight", value=0.664),
                decay=widgets.FloatText(description="First Message Deliveries Decay", value=0.9916),
                cap=widgets.FloatText(description="First Message Deliveries Cap", value=1500),
            ),
            mesh_message_deliveries=Bunch(
                weight=widgets.FloatText(description="Mesh Message Deliveries Weight", value=-0.25),
                decay=widgets.FloatText(description="Mesh Message Deliveries Decay", value=0.97),
                cap=widgets.FloatText(description="Mesh Message Deliveries Cap", value=400),
                threshold=widgets.FloatText(description="Mesh Message Deliveries Threshold", value=100),
                activation=widgets.Text(description="Mesh Message Deliveries Activation", value="30s"),
                window=widgets.Text(description="Mesh Message Delivery Window", value="5ms"),
            ),
            mesh_failure_penalty=Bunch(
                weight=widgets.FloatText(description="Mesh Failure Penalty Weight", value=-0.25),
                decay=widgets.FloatText(description="Mesh Failure Penalty Decay", value=0.997),
            ),
            invalid_message_deliveries=Bunch(
                weight=widgets.FloatText(description="Invalid Message Deliveries Weight", value=-99),
                decay=widgets.FloatText(description="Invalid Message Deliveries Decay", value=0.9994),
            )
        )

        topic_panel = widgets.VBox([
            labeled(self.topic_widgets.name),
            labeled(self.topic_widgets.message_rate),
            labeled(self.topic_widgets.message_size),
        ])

        score_panel = widgets.VBox([
            widgets.HTML('<h3>Peer Score Params</h3>'),
            labeled(self.topic_weight),
            to_collapsible_sections(self.score_widgets)],
            layout={'width': '900px'})

        self.panel = widgets.VBox([topic_panel, score_panel], layout={'width': '900px'})

    def ui(self):
        return self.panel

    def snapshot(self):
        return {
            'topic_weight': {'value': self.topic_weight.value},
            'topic': widget_snapshot(self.topic_widgets),
            'score': widget_snapshot(self.score_widgets),
        }

    def apply_snapshot(self, snapshot):
        if 'topic_weight' in snapshot and 'value' in snapshot['topic_weight']:
            self.topic_weight.value = snapshot['topic_weight']['value']
        if 'topic' in snapshot:
            apply_snapshot(self.topic_widgets, snapshot['topic'])
        if 'score' in snapshot:
            apply_snapshot(self.score_widgets, snapshot['score'])

    def topic_id(self):
        return self.topic_widgets.name.value

    def topic_params(self):
        return {
            'id': self.topic_widgets.name.value,
            'message_rate': self.topic_widgets.message_rate.value,
            'message_size': self.topic_widgets.message_size.value,
        }

    def score_params(self):
        p = {
            'TopicWeight': self.topic_weight.value,
        }
        for group in self.score_widgets.values():
            for param in group.values():
                key = param.description.replace(' ', '')
                p[key] = param.value
        return p


# ConfigPanel is a collection of widgets to set the test parameters.
class ConfigPanel(object):

    def __init__(self):
        # all the widgets used to configure the test

        default_out_dir = os.path.join('.', 'output', 'pubsub-test-{}'.format(time.strftime("%Y%m%d-%H%M%S")))
        default_failed_dir = os.path.join('.', 'output', 'failed')
        w = Bunch(
            test_execution=Bunch(
                output_dir=widgets.Text(description="Local directory to collect test outputs", value=default_out_dir),
                failed_dir=widgets.Text(description="Local dir to store output from failed runs", value=default_failed_dir)
            ),

            testground=Bunch(
                daemon_endpoint=widgets.Text(description="Daemon Endpoint", value='localhost:8080'),
                builder=widgets.Dropdown(description="Builder", options=['docker:go', 'exec:go']),
                runner=widgets.Dropdown(description="Runner", options=['cluster:k8s', 'local:docker', 'local:exec']),
                plan_dir=widgets.Text(description="Subdir of $TESTGROUND_HOME/plans containing pubsub plan", value="test-plans/pubsub/test"),
                keep_service=widgets.Checkbox(description="Keep pods after execution? (k8s only)", value=False),
                log_level=widgets.Dropdown(description="Log level to set on test instances", options=["info", "debug", "warn", "error"]),
            ),

            time=Bunch(
                setup=widgets.Text(description="Test Setup time", value='1m'),
                run=widgets.Text(description="Test Runtime", value='2m'),
                warm=widgets.Text(description="Warmup time", value='5s'),
                cool=widgets.Text(description="Cooldown time", value='10s'),
            ),

            node_counts=Bunch(
                total=widgets.IntText(description="Total number of test instances", disabled=True),
                total_peers=widgets.IntText(description="Total number of peers in all containers", disabled=True),
                publisher=widgets.IntText(description="Number of publisher nodes", value=100),
                lurker=widgets.IntText(description="Number of lurker nodes", value=50),
                honest_per_container=widgets.IntText(description="# of honest peers per container", value=1),
            ),

            pubsub=Bunch(
                branch=widgets.Text(description="go-libp2p-pubsub branch/tag/commit to target", value="master"),
                use_hardened_api=widgets.Checkbox(description="target hardening branch API", value=True),
                heartbeat=widgets.Text(description='Heartbeat interval', value='1s'),
                hearbeat_delay=widgets.Text(description='Initial heartbeat delay', value='100ms'),
                validate_queue_size=widgets.IntText(description='Size of validation queue', value=32),
                outbound_queue_size=widgets.IntText(description='Size of outbound RPC queue', value=32),
                score_inspect_period=widgets.Text(description='Interval to dump peer scores', value='5s'),
                full_traces=widgets.Checkbox(description='Capture full event traces)', value=False),
                degree=widgets.IntText(description='D: target mesh degree', value=10),
                degree_lo=widgets.IntText(description='D_lo: mesh degree low bound', value=8),
                degree_hi=widgets.IntText(description='D_hi: mesh degree upper bound', value=16),
                degree_score=widgets.IntText(description='D_score: peers to select by score', value=5),
                degree_lazy=widgets.IntText(description='D_lazy: lazy propagation degree', value=12),
                gossip_factor=widgets.FloatText(description='Gossip Factor', value=0.25),
                opportunistic_graft_ticks=widgets.IntText(description='Opportunistic Graft heartbeat ticks', value=60),
            ),

            network=Bunch(
                latency = widgets.Text(description="Min latency", value='5ms'),
                max_latency = widgets.Text(description="Max latency. If zero, latency will = min latency.", value='50ms'),
                jitter_pct = widgets.IntSlider(description="Latency jitter %", value=10, min=1, max=100),
                bandwidth_mb = widgets.IntText(description="Bandwidth (mb)", value=10240),
                degree=widgets.IntText(description="Degree (# of initial connections) for honest peers", value=20),

                # TODO: support upload of topology file
                # topology_file = widgets.FileUpload(description="Upload fixed topology file", accept='.json', multiple=False),
            ),

            honest_behavior=Bunch(
                flood_publishing=widgets.Checkbox(value=True, description='Flood Publishing', indent=False),
                connect_delay = widgets.Text(description='Honest peer connection delay. e.g. "30s" or "50@30s,30@1m"', value='0s'),
                connect_jitter_pct = widgets.BoundedIntText(description='Jitter % for honest connect delay', value=5, min=0, max=100),
            ),

            peer_score=Bunch(
                gossip_threshold=widgets.FloatText(description='Gossip Threshold', value=-4000),
                publish_threshold=widgets.FloatText(description='Publish Threshold', value=-5000),
                graylist_threshold=widgets.FloatText(description='Graylist Threshold', value=-10000),
                acceptpx_threshold=widgets.FloatText(description='Accept PX Threshold', value=0),
                opportunistic_graft_threshold=widgets.FloatText(description='Opportunistic Graft Threshold', value=0),
                ip_colocation_weight=widgets.FloatText(description='IP Colocation Factor Weight', value=0),
                ip_colocation_threshold=widgets.IntText(description='IP Colocation Factor Threshold', value=1),
                decay_interval=widgets.Text(description='Score Decay Interval', value='1s'),
                decay_to_zero=widgets.FloatText(description='Decay Zero Threshold', value=0.01),
                retain_score=widgets.Text(description="Time to Retain Score", value='30s'),
            )
        )

        # wire up node count widgets to calculate and show the total number of containers and peers
        # and update when the params they're derived from change
        sum_values(w.node_counts.total, w.node_counts.publisher, w.node_counts.lurker)
        mul_values(w.node_counts.total_peers, w.node_counts.total, w.node_counts.honest_per_container)


        self.topic_config = TopicConfigPanel()

        self.save_widgets = Bunch(
            save_button = widgets.Button(description='Save Config', button_style='primary'),
            load_button = widgets.Button(description='Load Saved Config', button_style='warning'),
            snapshot_filename = widgets.Text(description='Path:', value='configs/snapshot.json')
        )

        self.save_widgets.save_button.on_click(self.save_clicked)
        self.save_widgets.load_button.on_click(self.load_clicked)
        save_panel = widgets.HBox(list(self.save_widgets.values()))

        self.panel = widgets.VBox([
            to_collapsible_sections(w),
            collapsible("Topic Config", [self.topic_config.ui()]),
            save_panel,
        ])

        self.widgets = w

    def ui(self):
        return self.panel

    def save_clicked(self, evt):
        filename = self.save_widgets.snapshot_filename.value
        with open(filename, 'wt') as f:
            json.dump(self.snapshot(), f)
        print('saved config snapshot to {}'.format(filename))

    def load_clicked(self, evt):
        filename = self.save_widgets.snapshot_filename.value
        with open(filename, 'rt') as f:
            snap = json.load(f)

        # HACK: ignore the test_execution.output_dir param from the snapshot, to
        # avoid overwriting the output of a prior run
        if 'test_execution' in snap.get('main', {}):
            del(snap['main']['test_execution']['output_dir'])

        self.apply_snapshot(snap)
        print('loaded config snapshot from {}'.format(filename))

    def snapshot(self):
        return {
            'main': widget_snapshot(self.widgets),
            'topic': self.topic_config.snapshot(),
        }

    def apply_snapshot(self, snapshot):
        if 'main' in snapshot:
            apply_snapshot(self.widgets, snapshot['main'])
        if 'topic' in snapshot:
            self.topic_config.apply_snapshot(snapshot['topic'])

    def template_params(self):
        w = self.widgets

        n_nodes = w.node_counts.total.value
        n_publisher = w.node_counts.publisher.value
        n_nodes_cont_honest = w.node_counts.honest_per_container.value
        n_honest_nodes = n_nodes
        n_honest_peers_total = n_honest_nodes * n_nodes_cont_honest
        n_container_nodes_total = n_honest_peers_total

        p = {
            # testground
            'TEST_BUILDER': w.testground.builder.value,
            'TEST_RUNNER': w.testground.runner.value,
            'TEST_PLAN': w.testground.plan_dir.value,

            # time
            'T_SETUP': w.time.setup.value,
            'T_RUN': w.time.run.value,
            'T_WARM': w.time.warm.value,
            'T_COOL': w.time.cool.value,

            # node counts
            'N_NODES': n_nodes,
            'N_CONTAINER_NODES_TOTAL': n_container_nodes_total,
            'N_PUBLISHER': n_publisher,
            'N_HONEST_PEERS_PER_NODE': n_nodes_cont_honest,

            # pubsub
            'T_HEARTBEAT': w.pubsub.heartbeat.value,
            'T_HEARTBEAT_INITIAL_DELAY': w.pubsub.hearbeat_delay.value,
            'T_SCORE_INSPECT_PERIOD': w.pubsub.score_inspect_period.value,
            'VALIDATE_QUEUE_SIZE': w.pubsub.validate_queue_size.value,
            'OUTBOUND_QUEUE_SIZE': w.pubsub.outbound_queue_size.value,
            'FULL_TRACES': w.pubsub.full_traces.value,
            'OVERLAY_D': w.pubsub.degree.value,
            'OVERLAY_DLO': w.pubsub.degree_lo.value,
            'OVERLAY_DHI': w.pubsub.degree_hi.value,
            'OVERLAY_DSCORE': w.pubsub.degree_score.value,
            'OVERLAY_DLAZY': w.pubsub.degree_lazy.value,
            'GOSSIP_FACTOR': w.pubsub.gossip_factor.value,
            'OPPORTUNISTIC_GRAFT_TICKS': w.pubsub.opportunistic_graft_ticks.value,

            # network
            'T_LATENCY': w.network.latency.value,
            'T_LATENCY_MAX': w.network.max_latency.value,
            'JITTER_PCT': w.network.jitter_pct.value,
            'BANDWIDTH_MB': w.network.bandwidth_mb.value,
            'N_DEGREE': w.network.degree.value,
            # TODO: load topology file
            'TOPOLOGY': {},

            # honest behavior
            'FLOOD_PUBLISHING': w.honest_behavior.flood_publishing.value,
            'HONEST_CONNECT_DELAY_JITTER_PCT': w.honest_behavior.connect_jitter_pct.value,

            # topic & peer score configs
            'TOPIC_CONFIG': self._topic_config(),
            'PEER_SCORE_PARAMS': self._peer_score_params(),
        }

        if w.pubsub.use_hardened_api.value:
            p['BUILD_SELECTORS'] = [run_helpers.HARDENED_API_BUILD_TAG]
        else:
            p['BUILD_SELECTORS'] = []

        p['GS_VERSION'] = run_helpers.pubsub_commit(w.pubsub.branch.value)

        run_config = ['log_level="{}"'.format(w.testground.log_level.value)]

        if w.testground.runner.value == 'cluster:k8s':
            buildopts = ['push_registry=true', 'registry_type="aws"']
            p['BUILD_CONFIG'] = '\n'.join(buildopts)
            if w.testground.keep_service.value:
                run_config.append('keep_service=true')

        p['RUN_CONFIG'] = '\n'.join(run_config)

        # if the connect_delay param doesn't specify a count,
        # make it apply to all honest nodes
        delay = w.honest_behavior.connect_delay.value
        if '@' not in delay:
            delay = '{}@{}'.format(n_honest_peers_total, delay)
        p['HONEST_CONNECT_DELAYS'] = delay
        return p

    def composition(self):
        return run_helpers.render_template(TEMPLATE, self.template_params())

    def _topic_config(self):
        # TODO: support multiple topics
        topics = [self.topic_config.topic_params()]
        return topics

    def _peer_score_params(self):
        p = {
            'Thresholds': {
                'GossipThreshold': self.widgets.peer_score.gossip_threshold.value,
                'PublishThreshold': self.widgets.peer_score.publish_threshold.value,
                'GraylistThreshold': self.widgets.peer_score.graylist_threshold.value,
                'AcceptPXThreshold': self.widgets.peer_score.acceptpx_threshold.value,
                'OpportunisticGraftThreshold': self.widgets.peer_score.opportunistic_graft_threshold.value,
            },
            'IPColocationFactorWeight': self.widgets.peer_score.ip_colocation_weight.value,
            'IPColocationFactorThreshold': self.widgets.peer_score.ip_colocation_threshold.value,
            'DecayInterval': self.widgets.peer_score.decay_interval.value,
            'DecayToZero': self.widgets.peer_score.decay_to_zero.value,
            'RetainScore': self.widgets.peer_score.retain_score.value,

            # TODO: support multiple topics
            'Topics': {self.topic_config.topic_id(): self.topic_config.score_params()}
        }
        return p


#### widget helpers ####

def labeled(widget):
    if widget.description is None or widget.description == '':
        return widget
    label = widget.description
    widget.style.description_width = '0'
    return widgets.VBox([widgets.Label(value=label), widget])


def collapsible(title, params, expanded=False):
    grid = widgets.Layout(width='900px', grid_template_columns="repeat(2, 400px)")
    inner = widgets.GridBox(params, layout=grid)
    a = widgets.Accordion(children=[inner])
    a.set_title(0, title)
    a.selected_index = 0 if expanded else None
    return a


def to_collapsible_sections(w, expanded=False):
    # build up vbox of collapsible sections
    sections = []
    for name, params in w.items():
        title = stringcase.sentencecase(name)
        children = []
        for p in params.values():
            children.append(labeled(p))

        sections.append(collapsible(title, children, expanded=expanded))
    return widgets.VBox(sections, layout={'width': '900px'})



# sets the value of target widget to the sum of all arg widgets and updates when values change
def sum_values(target, *args):
    def callback(change):
        if change['name'] != 'value':
            return
        target.value = functools.reduce(operator.add, [a.value for a in args])

    for widget in args:
        widget.observe(callback)

    # trigger callback to set initial value
    callback({'name': 'value'})


# sets the value of target widget to the product of all arg widgets and updates when values change
def mul_values(target, *args):
    def callback(change):
        if change['name'] != 'value':
            return
        target.value = functools.reduce(operator.mul, [a.value for a in args])

    for widget in args:
        widget.observe(callback)

    # trigger callback to set initial value
    callback({'name': 'value'})


# takes a nested dict (or Bunch) whose leaves are widgets,
# and returns a dict with the same structure, but with widgets replaced with
# a snapshot of their current values
def widget_snapshot(widgets):
    out = dict()
    for name, val in widgets.items():
        if isinstance(val, Bunch) or isinstance(val, dict):
            out[name] = widget_snapshot(val)
        else:
            w = {'value': val.value}
            out[name] = w
    return out


# takes a nested dict or Bunch of widgets and the output of widget_snapshot,
# and sets the current widget values to the values from the snapshot
def apply_snapshot(widgets, snapshot):
    for name, val in widgets.items():
        if name not in snapshot:
            continue
        if isinstance(val, Bunch) or isinstance(val, dict):
            apply_snapshot(val, snapshot[name])
        else:
            s = snapshot[name]
            if 'value' in s:
                val.value = s['value']
