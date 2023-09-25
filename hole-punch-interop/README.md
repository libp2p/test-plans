# Hole punch tests

## How to run locally

1. `npm run install`
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
