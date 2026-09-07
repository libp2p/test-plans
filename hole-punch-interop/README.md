# Hole punch tests

## How to run locally

1. `npm install`
2. `make`
3. `npm run test`

## Client configuration

| env variable | possible values |
|--------------|-----------------|
| MODE         | listen \| dial  |
| TRANSPORT    | tcp \| quic     |

- For TCP, the client MUST use noise + yamux to upgrade the connection.
- The relayed connection MUST use noise + yamux.

## Test flow

1. The relay starts and pushes its address to the following redis keys:
   - `RELAY_TCP_ADDRESS` for the TCP test
   - `RELAY_QUIC_ADDRESS` for the QUIC test
1. Upon start-up, clients connect to a redis server at `redis:6379` and block until this redis key comes available.
   They then dial the relay on the provided address.
1. The relay supports identify.
   Implementations SHOULD use that to figure out their external address next.
1. Once connected to the relay, a client in `MODE=listen` should listen on the relay and make a reservation.
   Once the reservation is made, it pushes its `PeerId` to the redis key `LISTEN_CLIENT_PEER_ID`.
1. A client in `MODE=dial` blocks on the availability of `LISTEN_CLIENT_PEER_ID`.
   Once available, it dials `<relay_addr>/p2p-circuit/<listen-client-peer-id>`.
1. Upon a successful hole-punch, the peer in `MODE=dial` measures the RTT across the newly established connection.
1. The RTT MUST be printed to stdout in the following format:
   ```json
   { "rtt_to_holepunched_peer_millis": 12 }
   ```
1. Once printed, the dialer MUST exit with `0`.

## Requirements for implementations

- Docker containers MUST have a binary called `hole-punch-client` in their $PATH
- MUST have `dig`, `curl`, `jq` and `tcpdump` installed
- Listener MUST NOT early-exit but wait to be killed by test runner
- Logs MUST go to stderr, RTT json MUST go to stdout
- Dialer and lister both MUST use 0RTT negotiation for protocols
- Implementations SHOULD disable timeouts on the redis client, i.e. use `0`
- Implementations SHOULD exit early with a non-zero exit code if anything goes wrong
- Implementations MUST set `TCP_NODELAY` for the TCP transport
- Implements MUST make sure connections are being kept alive

## Design notes

The design of this test runner is heavily influenced by [multidim-interop](../multidim-interop) but differs in several ways.

All files related to test runs will be written to the [./runs](./runs) directory.
This includes the `docker-compose.yml` files of each individual run as well as logs and `tcpdump`'s for the dialer and listener.

The docker-compose file uses 6 containers in total:

- 1 redis container for orchestrating the test
- 1 [relay](./relay/rust)
- 1 hole-punch client in `MODE=dial`
- 1 hole-punch client in `MODE=listen`
- 2 [routers](./router): 1 per client

The networks are allocated by docker-compose.
We dynamically fetch the IPs and subnets as part of a startup script to set the correct IP routes.  

In total, we have three networks:

1. `lan_dialer`
2. `lan_listener`
3. `internet`

The two LANs host a router and a client each whereas the relay is connected (without a router) to the `internet` network.
On startup of the clients, we add an `ip route` that redirects all traffic to the corresponding `router` container.
The router container masquerades all traffic upon forwarding, see the [README](./router/README.md) for details.

The `internet` network is pinned to a routable `/24` in `11.0.0.0/8`, one per test.
go-libp2p starts its DCUtR service only once the host holds an address that `manet.IsPublicAddr` accepts, and a peer's observed address is its router's internet-side IP.
Docker's default pool is RFC1918, which go filters out of its hole-punch candidates, so on the default pool go never begins a hole punch.
The two LANs stay on the default pool because the peers genuinely are behind NAT there.

## Relay implementation

The relay is a shared component. `RELAY_IMPL` selects which one runs, defaulting to `rust`:

| value  | directory                  |
|--------|----------------------------|
| `rust` | [`relay/rust`](./relay/rust) |
| `go`   | [`relay/go`](./relay/go)     |

Both listen on TCP and QUIC at once and push their `/p2p`-suffixed address twice to `RELAY_TCP_ADDRESS` and `RELAY_QUIC_ADDRESS`.

## Known-failing implementations

`js-v3.x` is in the matrix but every js cell fails, so CI ignores them
(`test-ignore js-v3.x`). js-libp2p DCUtR performs only the unilateral direct-dial
upgrade; bilateral hole punching over TCP does not work. Node.js does not support
`SO_REUSEPORT`, so identify drops every observed TCP address and the
simultaneous-open dial uses a fresh source port rather than the listener's. The
client then advertises only undialable addresses, and the punch never completes.
Official js-libp2p also does not include a QUIC transport. The impl is kept in 
the matrix so a future js-libp2p release can be retested by dropping the ignore. See
[issue 2620](https://github.com/libp2p/js-libp2p/issues/2620) and
[discussion 2388](https://github.com/libp2p/js-libp2p/discussions/2388).

## Running a single test

1. Build all containers using `make`
1. Generate all test definitions using `npm run test -- --no-run`
1. Pick the desired test from the [runs](./runs) directory
1. Execute it using `docker compose up`
