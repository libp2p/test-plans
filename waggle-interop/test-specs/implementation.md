# Specification for running an Implementation in the Waggle interop testing framework

This document specifies the requirements that a Waggle implementation must
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

Implementations will be provided a path to a `params.json` file as CLI
argument (e.g. `--params <params.json>`). This JSON file contains the JSON
encoded value of an `ExperimentParams` type (see `experiment.py`).

Implementations MUST parse this file and use the values to run the experiment.

### Script Instructions

Script instructions are how each node knows what to do during the experiment.
Implementations MUST handle each instruction. See `script_instruction.py` for
the instructions you need to support. The instructions are included in the
ExperimentParams.script passed in via the `params.json` file.

## Output

Implementations MUST reserve STDOUT as their output channel and use STDERR for
diagnostics and errors.

Implementations MUST log their STDOUT events using a structured
newline-delimited JSON logging format.

All STDOUT logs must include the following fields:
- time: The RFC3339 timestamp of the log entry.
- msg: The message being logged.

Implementations MUST log at least the following events:

- PeerID on start. When starting, implementations MUST log the message `"PeerID"` along with the following fields:
  - id: The peer ID of the node as a string.
  - node_id: The node ID of this node as an integer.

- All parts received. This event MUST be logged every time a node completes the
  reconstruction of an object (i.e. it holds all pieces of an object). This
  event MUST be logged with `msg="All parts received"` and the following
  additional fields:
  - object_id: The object id of the reconstructed object.

  Example:

  New lines added for readability, implementations MUST NOT add new new lines within a JSON object.
  ```json
  {
    "time": "1999-12-31T16:08:12.4030048-08:00",
    "level": "INFO",
    "msg": "All parts received",
    "object_id": "31"
  }
  ```

## Piece wire format

An object is split into up to 8 pieces, each `1024` bytes long. The pieces of
an object are identified by a `piecesMetadata` bitmap where bit `i` set means
the node holds piece `i`.

The protocol fields are populated as follows:

- `objectID`: The 8 byte big-endian encoding of the object id.
- `piecesMetadata`: A single byte whose bit `i` is set when the node holds piece `i`.
- `pieces`: A single leading bitmap byte followed by the concatenation of the
  payloads of the pieces the sender has that the receiver is missing, in
  ascending piece order. Bit `i` of the leading byte is set when piece `i` is
  present in the payload. Each piece payload is `1024` bytes.

When logging the object id, implementations MUST format the object id as a
base 10 integer.
