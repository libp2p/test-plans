# `Plan:` Nodes Connectivity (Transports, Hole Punching, Relay)

![](https://img.shields.io/badge/status-wip-orange.svg?style=flat-square)

Ensuring that a node can always connect to the rest of the network, if not completely isolated.

## What is being optimized (min/max, reach)

- (Reach) The number of nodes that are able to dial to any other node (100%)

## Plan Parameters

- **Network Parameters**
  - `Region` - Region or Regions where the test should be run at (default to single region)
  - Ran with with an arbitraty amount of nodes (from 10 to 1000000) - N
  - Nodes being beyind a NAT/Firewall - F (F is a % of N)
  - Nodes running the Image with IPFS on a Browser - B (B is a % of N)
  - Nodes running the Image with go-ipfs using only TCP - T (T is a % of N)
  - Nodes running the Image with go-ipfs using only QUIC - Q (Q is a % of N)
  - Nodes running the Image with go-ipfs using only WebSockets - W (W is a % of N)
  - Nodes running the Image with go-ipfs using only WebRTC - C (C is a % of N)
- **Image Parameters**
  - Image A - Base `go-ipfs`
    - `Transport` The only transport to be used
  - Image B - Base `js-ipfs` running in a Browser
    - `Browser` The Browser in which js-ipfs will be running from

## Tests

### `Test:` TCP hole punching

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d

## `Test:` uTP hole punching

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d

### `Test:` QUIC hole punching

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d

## `Test:` WebRTC hole punching

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d

## `Test:` Circuit Relay (between all transports combinations)

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d

## `Test:` go-ipfs to js-ipfs to browser Interop (Transports & Relay)

- **Test Parameters**
  - n/a
- **Narrative**
  - **Warm up**
    - Create the Bootstrapper nodes that are connected among themselves and support every transport
  - **Act I**
    - b
  - **Act II**
    - c
  - **Act III**
    - d
