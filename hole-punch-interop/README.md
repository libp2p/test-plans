# Hole punch tests

## How to run locally

1. `npm run install`
2. `make`
3. `npm run test`

## Design

- TODO

## Requirements for implementations

- Docker containers MUST have a binary called `hole-punch-client` in their $PATH
- Must have `dig`, `curl` and `jq` installed
- Dialer must print RTT to hole-punched peer over new connection, then exit
- Listener must never exit successfully but wait to be killed by test runner
- Logs MUST go to stderr, RTT json MUST go to stdout
- Dialer and lister both MUST use 0RTT negotiation for protocols
- Implementations should disable timeouts on the redis client, i.e. use `0`
- Implementations should exit early with a non-zero exit code if anything goes wrong
- Implementations MUST set `TCP_NODELAY` for the TCP transport
