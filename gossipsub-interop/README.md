# GossipSub Interop testing framework

## Overview

This framework is designed to reproducibly test interoperability between
different GossipSub implementations. It can also be used to benchmark the effect
of different implementations and protocol designs in a controlled simulation.

This framework leverages [Shadow](https://shadow.github.io/) as its simulator.

There are two components to our interoperability test:

1. The _scenario_ we are running. This defines the specific actions each node in
   the network takes at a specific point in time. Actions such as publishing a
   message, connecting to other nodes, or subcribing. See `script_action.py` for a
   list of actions.
2. The _composition_ of the network. This defines what percent of the network is
   running what implementation. For example you can have a network composed of 50%
   go-libp2p nodes and 50% rust-libp2p nodes.

A key aspect of this framework is that scenarios, compositions, and GossipSub
parameters can be modified without modifying implementations. See `experiment.py`, where this can be configured

After running a test, there are three key results we can extract from the simulation:

1. The _reliability_ of the message dissemenation. This is the percentage of
   nodes that a message was delivered to.
2. The dissementation _latency_ to disseminate the message.
3. The _bandwidth efficiency_ in terms of the number of _duplicate messages_ received.

Implementations are deemed interoperable if variations in composition do not
result in any significant differences in observed behavior or outputs. For
example, a network of all go-libp2p nodes should behave the same as a network
with an even mix of go-libp2p and rust-libp2p nodes.

## Requirements

- [Shadow](https://shadow.github.io/) for shadow experiments.
- [uv](https://docs.astral.sh/uv/) for python dependencies.
- Implementation specific requirements for building the implementations (Go, Rust, etc...)

## Running a simulation

```bash
uv run run.py --help
```

For example, to run a simulation with an even mix of go-libp2p and rust-libp2p
nodes with default GossipSub parameters and sending large messages to a network
of 700 nodes:

```bash
uv run run.py --node_count 700 --composition "rust-and-go" --scenario "subnet-blob-msg"
```

The definitions of the experiment, composition, and scenarios are defined in `experiment.py`.

After running an experiment all the results and configuration needed to
reproduce the test are saved in an output folder which, by default, is named by
the specific scenario, node count, and composition. For the above
example, the output folder is
`subnet-blob-msg-700-rust-and-go.data`. This output folder contains the following files:

- shadow.yaml: The Shadow config defining the binaries and network.
- graph.gml: The graph of the network links for Shadow.
- params.json: The parameters passed to each binary with GossipSub parameters and the actions to run.
- plots/
  - analysis_*.txt: A text file containing a high level analysis of the 3 key results
  - Charts visualizing the results.

## Adding an implementation

To build the implementation reference `./test-specs/implementation.md`.

After implementing it, make sure to add build commands in the Makefile's `binaries` recipe.

Finally, add it to the `composition` function in `experiment.py`.

## Future work (contributions welcome)

- Add more scenarios.
- Add other implementations.
- Add more plots and visualizations.
- Add a helper to make it easier to rerun an experiment given an output folder.
- Add to CI
