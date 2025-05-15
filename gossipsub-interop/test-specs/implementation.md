# Specification for running an Implementation in the GossipSub interop testing framework

This document specifies the requirements that a GossipSub implementation must
fulfill in order to be testable.

## Node IDs

Each node in the simulation is given a unique integer ID from 0 to `num_nodes-1`. Implementations can learn their node id by calling `hostname`. Example:

```go
	hostname, err := os.Hostname()
	var nodeId int
	_, err = fmt.Sscanf(hostname, "node%d", &nodeId)
```

## Peer IDs

Implementations MUST deterministically generate their ED25519 peer ID from their node ID by using their little-endian encoded node ID as their ED25519 key.

Example:
```rust
pub fn node_priv_key(id: NodeID) -> identity::Keypair {
    let mut seed = [0u8; 32];
    LittleEndian::write_i32(&mut seed[0..4], id);
    identity::Keypair::ed25519_from_bytes(seed).expect("Failed to create keypair")
}
```

## Input

Implementations will be provided a path to path to a `params.json` file. This JSON
file contains the JSON encoded value of a `ExperimentParams` type (see `experiment.py`).

Implementations MUST parse this file and use the values to run the experiment.


### gossipSubParams

This is a JSON encoded value of go-libp2p-pubsub's
[`GossipSubParams`](https://github.com/MarcoPolo/go-libp2p-pubsub/blob/0c5ee7bbfeb051200bc39eb824246cc651f7358a/gossipsub.go#L85)
type.

This may change in the future.

### Script Actions

Script actions are how each node knows what to do during the experiment.
Implementations MUST handle each action. See `script_action.py` for the actions
you need to support.

## Output

Implementations MUST reserve STDOUT as their output channel and use STDERR for
diagnostics and errors.

Implementations MUST log their STDOUT events using a structured JSON logging format.

All STDOUT logs must include the following fields:
- time: The RFC3339 timestamp of the log entry.
- msg: The message being logged.

Implementations MUST log at least the following events:

- PeerID on start. When starting, implementations MUST log the message `"PeerID"` along with the following fields:
  - id: The peer ID of the node as a string.
  - node_id: The node ID of this node as an integer.

- Received message. This event MUST be logged every time a message is received,
  including duplicate messages. This event MUST be logged with `msg="Received
  Message"` and the following additional fields.
  - id: The message id of the message as a string.

  - Implementations SHOULD log these additional fields (currently unused by the analysis):
    - from: The peer ID of the sender (not the original publisher).
    - topic: The topic string of the message.

  Example:

  New lines added for readability, implementations MUST NOT add new new lines within a JSON object.
  ```json
  {
    "time": "1999-12-31T16:08:12.4030048-08:00",
    "level": "INFO",
    "msg": "Received Message",
    "service": "gossipsub",
    "from": "12D3KooWJTwhQuDG8K7z5rXpB2n9VtFY5wevFWEj9s4HUWt5nvgj",
    "topic": "foobar",
    "id": "31"
  }
  ```

## Message Format

Message ID is calculated by reading the first 8 bytes of the message and
interpreting them as a big endian encoded 64 bit unsigned integer.

Messages MUST be sized to the specified `messageSizeBytes` parameter.
