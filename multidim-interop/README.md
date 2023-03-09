# Interoperability test

This tests that different libp2p implementations can communicate with each other
on each of their supported capabilites.

Each version of libp2p is defined in `versions.ts`. There the version defines
its capabilities along with the id of its container image.

# Test spec

The implementation is run in a container and is passed parameters via
environment variables. The current parameters are:

| Name                 | Description                                                  | Is Optional                                                         |
| -------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------- |
| transport            | The transport to use                                         | no                                                                  |
| muxer                | The muxer to use                                             | no, except when transport is one of quic, quic-v1, webtransport     |
| security             | The security channel to use                                  | no, except when transport is one of quic, quic-v1, webtransport     |
| is_dialer            | Should you dial or listen                                    | no                                                                  |
| ip                   | IP address to bind the listener to                           | yes, default to "0.0.0.0"                                           |
| redis_addr           | A different address to connect to redis (default redis:6379) | yes, default to the `redis` host on port 6379                       |
| test_timeout_seconds | Control the timeout of test.                                 | yes, default to 180 seconds.                                        |
| relay_addr           | Multiaddr for the relay                                      | yes, only passed in when `addRelay` is set to true in the transport |

The test should do two different things depending on if it's the dialer or
listener.

## Dialer

The dialer should emit all diagnostic logs to `stderr`. Only the final JSON
string result should be emitted to `stdout`.

1. Connect to the Redis instance.
2. Create a libp2p node as defined by the environment variables.
3. Get the listener's address via Redis' `BLPOP` using the `listenerAddr` key.
4. Record the current instant as `handshakeStartInstant`.
5. Connect to the listener.
6. Ping the listener, and record the round trip duration as `pingRTT`
7. Record the duration since `handshakeStartInstant`. This is `handshakePlusOneRTT`.
8. Print to `stdout` the JSON formatted string: `{"handshakePlusOneRTTMillis":
   handshakePlusOneRTT, "pingRTTMilllis": pingRTT}`. Durations should be printed in
   milliseconds as a float.
9.  Exit with a code zero.

On error, the dialer should return a non-zero exit code.

## Listener

The listener should emit all diagnostic logs to `stderr`.

1. Connect to the Redis instance.
2. Create a libp2p node as defined by the environment variables.
3. Publish the listener's address via Redis' `RPUSH` using the `listenerAddr`
   key.
4. Sleep for the duration of `test_timeout_seconds`. The test runner will kill this
   process when the dialer finishes.
5. If the timeout is hit, exit with a non-zero error code.

On error, the listener should return a non-zero exit code.