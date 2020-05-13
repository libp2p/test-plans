# `Plan:` gossipsub performs at scale

This test plan evaluates the performance of gossipsub, the gossiping mesh routing protocol
implemented by [go-libp2p-pubsub](https://github.com/libp2p/go-libp2p-pubsub).

## Installation & Setup

We're using python to generate testground composition files, and we shell out to a few 
external commands, so there's some environment setup to do.

### Requirements

#### Hardware

While no special hardware is needed to run the tests, running with a lot of test instances requires considerable CPU and
RAM, and will likely exceed the capabilities of a single machine.

A large workstation with many CPU cores can reasonably run a few hundred instances using the testground
`local:docker` runner, although the exact limit will require some trial and error. In early testing we were able to
run 500 containers on a 56 core Xeon W-3175X with 124 GiB of RAM, although it's possible we could run more
now that we've optimized things a bit.

It's useful to run with the `local:docker` or `local:exec` runners during test development, so long as you use
fairly small instance counts (~25 or so works fine on a 2018 13" MacBook Pro with 16 GB RAM).

When using the `local:docker` runner, it's a good idea to periodically garbage collect the docker images created by
testground using `docker system prune` to reclaim disk space.

To run larger tests like the ones in the [saved configurations](#saved-test-configurations), you'll need a
kubernetes cluster. 

To create your own cluster, follow the directions in the [testground/infra repo](https://github.com/testground/infra)
to provision a cluster on AWS, and configure your tests to use the `cluster:k8s` test runner.

The testground daemon process can be running on your local machine, as long as it has access to the k8s cluster.
The machine running the daemon must have Docker installed, and the user account must have permission to use
docker and have the correct AWS credentials to connect to the cluster. 
When running tests on k8s, the machine running the testground daemon doesn't need a ton of resources,
but ideally it should have a fast internet connection to push the Docker images to the cluster.

Running the analysis notebooks benefits from multiple cores and consumes quite a bit of RAM, especially on the first
run when it's converting data to pandas format. It's best to have at least 8 GB of RAM free when running the analysis
notebook for the first time. 

Also note that closing the browser tab containing a running Jupyter notebook does not stop the python kernel and reclaim
the memory used. It's best to select `Close and Halt` from the Jupyter `File` menu when you're done with the analysis 
notebook instead of just closing the tab.

#### Testground

You'll need to have the [testground](https://github.com/testground/testground) binary built and accessible
on your `$PATH`. Testground must be version 0.5.0 or newer.

After running `testground list` for the first time, you should have a `~/testground` directory. You can change this
to another location by setting the `TESTGROUND_HOME` environment variable.

#### Cloning this repo

The testground client will look for test plans in `$TESTGROUND_HOME/plans`, so this repo should be cloned or
symlinked into there:

```shell
cd ~/testground/plans # if this dir doesn't exist, run 'testground list' once first to create it
git clone git@github.com:libp2p/test-plans libp2p-plans
```

#### Python

We need python 3.7 or later, ideally in a virtual environment. If you have python3 installed, you can create
a virtual environment named `venv` in this repo and it will be ignored by git:

```shell
python3 -m venv venv
```

After creating the virtual environment, you need to "activate" it for each shell session:

```shell
# bash / zsh:
source ./venv/bin/activate

# fish:
source ./venv/bin/activate.fish
```

You'll also need to install the python packages used by the scripts:

```shell
pip install -r scripts/requirements.txt
```

#### External binaries

The run scripts rely on a few commands being present on the `PATH`:

- the `testground` binary
- `go`

## Running Tests

### Running using the Runner Jupyter notebook

With the python virtualenv active, run 

```shell
jupyter notebook
```

This will start a Jupyter notebook server and open a browser to the Jupyter file navigator.
In the Jupyter UI, navigate to the `scripts` dir and open `Runner.ipynb`.

This will open the runner notebook, which lets you configure the test parameters using a
configuration UI.

You'll need to run all the cells to prepare the notebook UI using `Cell menu > Run All`. You can reset
the notebook state using the `Kernel Menu > Restart and Run All` command.

The cell at the bottom of the notebook has a "Run Test" button that will convert the configured parameters
to a composition file and start running the test. It will shell out to the `testground` client binary,
so if you get an error about a missing executable, make sure `testground` is on your `PATH` and restart
the Jupyter server.

At the end of a successful test, there will be a new `output/pubsub-test-$timestamp` directory (relative to
the `scripts` dir) containing the composition file, the full `test-output.tgz` file collected from testground,
and an `analysis` directory.

The `analysis` directory has relevant files that were extracted from the `test-output.tgz` archive, along with a
new Jupyter notebook, `Analysis.ipynb`. See below for more details about the analysis notebook.

If the test fails (`testground` returns a non-zero exit code), the runner script will move the `pubsub-test-$timestamp`
dir to `./output/failed`.

The "Test Execution" section of the config UI will let you override the output path, for example if you want
to give your test a meaningful name.

### Targeting a specific version of go-libp2p-pubsub

The default configuration is to test against the current `master` branch of go-libp2p-pubsub,
but you can change that in the `Pubsub` panel of the configuration UI. You can enter the name
of a branch or tag, or the full SHA-1 hash of a specific commit.

**Important:** if you target a version before [the Gossipsub v1.1 PR](https://github.com/libp2p/go-libp2p-pubsub/pull/273)
was merged, you must uncheck the "target hardening branch API" checkbox to avoid build failures due to
missing methods.

#### Saved test configurations

You can save configuration snapshots to JSON files and load them again using the buttons at the bottom
of the configuration panel. The snapshots contain the state of all the configuration widgets, so can
only be used with the Runner notebook, not the command line `run.py` script.

There are several saved configs in `scripts/configs` that we've been using to evaluate different scenarios. 

There are subdirectories inside of `scripts/configs` corresponding to different `testground` Runners, and
there are a few configurations for each runner with various node counts. For example, `configs/local-exec/25-peers.json`
will create a composition for the test using the `exec:go` builder and `local:exec` runner, with 25 pubsub peers,
while `configs/local-docker/25-peers.json` will use the `docker:go` and `local:docker` runner.

The saved configs all expect to find the `testground` daemon on a non-standard port (8080 instead of 8042). 
If you're not running the daemon on port 8080, you can change the endpoint in the `Testground` section of
the config UI, or tell the daemon to listen on 8080 by editing `~/testground/.env.toml`.

### Running using the cli scripts

Inside the `scripts` directory, the `run.py` script will generate a composition and run it by shelling out to
`testground`. If you just want it to generate the composition, you can skip the test run by passing the `--dry-run`
flag.

You can get the full usage by running `./run.py --help`.

To run a test with baseline parameters (as defined in `scripts/templates/baseline/params/_base.toml`), run:

```shell
./run.py
```

By default, this will create a directory called `./output/pubsub-test-$timestamp`, which will have a `composition.toml`
file inside, as well as a `template-params.toml` that contains the params used to generate the composition.

You can control the output location with the `-o` and `--name` flags, for example:

```shell
./run.py -o /tmp --name 'foo'
# creates directory at /tmp/pubsub-test-$timestamp-foo
```

Note that the params defined in `scripts/templates/baseline/params/_base.toml` have very low instance counts and
are likely useless for real-world evaluation of gossipsub.

You can override individual template parameters using the `-D` flag, for example, `./run.py -D T_RUN=5m`.
There's no exhaustive list of template parameters, so check the template at `scripts/templates/baseline/template.toml.j2`
to see what's defined.

Alternatively, you can create a new toml file containing the parameters you want to set, and it will override
any parameters defined in `scripts/templates/baseline/params/_base.toml`

By default, the `run.py` script will extract the test data from the collected test output archive and copy the
analysis notebook to the `analysis` subdirectory of the test output dir. If you want to skip this step,
you can pass the `--skip-analysis` flag.

## Analyzing Test Outputs

After running a test, there should be a directory full of test outputs, with an `analysis` dir containing
an `Analysis.ipynb` Jupyter notebook. If you're not already running the Jupyter server, start it with
`jupyter notebook`, and use the Jupyter UI to navigate to the analysis notebook and open it.

Running all the cells in the analysis notebook will convert the extracted test data to 
[pandas](https://pandas.pydata.org/) `DataFrame`s. This conversion takes a minute or two depending on the
size of the test and your hardware, but the results are cached to disk, so future runs should be pretty fast.

Once everything is loaded, you'll see some charts and tables, and there will be a new `figures` directory inside the 
`analysis` dir containing the charts in a few image formats. There's also a `figures.zip` with the same contents
for easier downloading / storage.

### Running the analysis notebook from the command line

If you just want to generate the charts and don't care about interacting with the notebook, you can execute
the analysis notebook using a cli script.

Change to the `scripts` directory, then run

```shell
./analyze.py run_notebook ./output/pubsub-test-$timestamp
```

This will copy the latest analysis notebook template into the `analysis` directory and execute the notebook, which
will generate the chart images. 

This command is useful if you've made changes to the analysis notebook template and want to re-run it against a
bunch of existing test outputs. In that case, you can pass multiple paths to the `run_notebook` subcommand:

 ```shell
 ./analyze.py run_notebook ./output/pubsub-test-*
# will run the latest notebook against everything in `./output
 ```

## Storing & Fetching Test Outputs in S3

The `scripts/sync_outputs.py` script is a wrapper around the [rclone](https://rclone.org) command that
helps backup test outputs to an s3 bucket, or fetch a previously stored output directory to the local filesystem.

The AWS credentials are pulled from the environment - see [the AWS cli docs](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
if you haven't already configured the aws cli to use your credentials. 
The configured user must have permission to access the bucket used to sync.

`rclone` must be installed and on the `$PATH` to use the `sync_outputs.py` script.

By default, it uses the S3 bucket `gossipsub-test-outputs` in `eu-central-1`, but you can control this with the
`--bucket` and `--region` flags.

To backup all the test outputs in `./output`:

```shell
./sync_outputs.py store-all ./output
``` 

It will ignore the `failed` subdirectory automatically, but if you want to ignore more, you can pass in a flag:

```shell
./sync_outputs.py store-all ./output --ignore some-dir-you-dont-want-to-store
``` 

Alternatively, you can selectively store one or more test outputs with the `store` subcommand:

```shell
./sync_outputs.py store ./output/pubsub-test-20200409-152658 ./output/pubsub-test-20200409-152983 # etc...
``` 

You can also fetch test outputs from S3 to the local filesystem.
To fetch everything from the bucket into `./output`:

```shell
./sync_outputs.py fetch-all ./output
``` 

Or, to fetch one or more tests from the bucket instead of everything:

```shell
./sync_outputs.py fetch --dest=./output pubsub-test-20200409-152658
``` 

You can list all the top-level directories in the S3 bucket (so you know what to fetch) using the `list` command:

```shell
./sync_outputs.py list
``` 

## Code Overview

The test code all lives in the `test` directory.

`main.go` is the actual entry point, but it just calls into the "real" main function, `RunSimulation`, which is defined
in `run.go`.

`params.go` contains the parameter parsing code. The `parseParams` function will return a `testParams` struct with
all test parameters.

The set of params provided to each test instance depends on which composition group they're in. The composition
template we're using defines two groups: `publishers`, and `lurkers`. The lurkers and publishers have
identical params with the exception of the boolean `publisher` param, which controls whether they will publish messages
or just consume them.

After parsing the params, `RunSimulation` will prepare the libp2p `Host`s, do some network setup and then
call `runPubsubNode` to begin the test.

`discovery.go` contains a `SyncDiscovery` component that uses the testground sync service to broadcast information about
the test peers (e.g. addreses, whether they're honest, etc) with every other peer. It uses this information to connect
nodes to each other in various topologies.

The honest node implementation is in `node.go`, and there are also `node_v10.go` and `node_v11.go` files
that allow us to target the new gossipsub v1.1 API or the old v1.0 API by setting a build tag. If the v1.0 API
is used, the test will not produce any peer score information, since that was added in v1.1.

The `tracer.go` file implements the `pubsub.EventTracer` interface to capture pubsub events and produce test metrics.
Because the full tracer output is quite large (several GB for a few minutes of test execution with lots of nodes),
we aggregate the trace events at runtime and spit out a json file with aggregated metrics at the end of the test.
We also capture a filtered subset of the original traces, containing only Publish, Deliver, Graft, and Prune events.
At the end of the test, we run [tracestat](https://github.com/libp2p/go-libp2p-pubsub-tracer/blob/master/cmd/tracestat/main.go)
on the filtered traces to calculate the latency distribution and get a summary of publish and deliver counts.
