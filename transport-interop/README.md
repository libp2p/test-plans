# Transport Interoperability tests

This tests that different libp2p implementations can communicate with each other
on each of their supported (transport) capabilities.

Each version of libp2p is defined in `versions.ts`. There the version defines
its capabilities along with the id of its container image.

This repo and tests adhere to these constraints:
1. Be reproducible for a given commit.
2. Caching is an optimization. Things should be fine without it.
3. If we have a cache hit, be fast.

# Test spec

The implementation is run in a container and is passed parameters via
environment variables. The current parameters are:

| Name                 | Description                                                  | Is Optional                                                     |
| -------------------- | ------------------------------------------------------------ | --------------------------------------------------------------- |
| transport            | The transport to use                                         | no                                                              |
| muxer                | The muxer to use                                             | no, except when transport is one of quic, quic-v1, webtransport |
| security             | The security channel to use                                  | no, except when transport is one of quic, quic-v1, webtransport |
| is_dialer            | Should you dial or listen                                    | no                                                              |
| ip                   | IP address to bind the listener to                           | yes, default to "0.0.0.0"                                       |
| redis_addr           | A different address to connect to redis (default redis:6379) | yes, default to the `redis` host on port 6379                   |
| test_timeout_seconds | Control the timeout of test.                                 | yes, default to 180 seconds.                                    |

The test should do two different things depending on if it's the dialer or
listener.

## Running Tests Locally using Docker images

1. Build the images of the implementations

   ```bash
   make
   ```

2. Install the dependencies need to run the tests

   ```bash
   npm install
   ```
3. Run the tests

   ```bash
   npm run test
   ```
**Note**:
You may only want to run specific versions, you can do so by passing the `--name-filter` flag
```bash
npm run test -- --name-filter js-libp2p-head
```
You can also ignore specific versions by passing the `--name-ignore` flag
```bash
npm run test -- --name-filter js-libp2p-head
```

## Adding an implementation

1. Add the implementation to new subdirectory in [`impl/*`](./impl/).
    - For a new implementation, create a folder `impl/<your-implementation-name>/` e.g. `go-libp2p`
    - For a new version of an existing implementation, create a folder `impl/<your-implementation-name>/<your-implementation-version>`.
    - In that folder include a `Makefile` that builds a docker image and stores it as `image.json`
    - Requirements for the executable:
2. Add the implementation to [`versions.ts`](./versions.ts).
3. Add the implementation (and it's subdirectories) [`Makefile`](./Makefile).
4. The implementation must implement a [ping](https://github.com/libp2p/specs/blob/50db89f3a71a87b096b0994a43a2dce0d251aeec/ping/ping.md) test, where it listens for a ping
   and responds with a pong. The test runner will measure the round trip time
   and the time it takes to establish the connection.
5. The implementation must accept the a `transport` flag which specifies which transport to use. e.g. `tcp`, `ws`, `quic`, `quic-v1`, `webtransport`.
6. The implementation must accept the a `muxer` flag which specifies which muxer to use. e.g. `mplex`, `yamux`.
7. The implementation may accept an `ip` flag which specifies which IP address to bind to. If not specified, the implementation should bind to `0.0.0.0`
8. The implementation must accept a `redis_addr` flag which specifies which address to connect to redis. If not specified, the implementation should connect to `redis:6379`
9. The implementation must accept a `test_timeout_seconds` flag which specifies the timeout of the test. If not specified, the implementation should use a default of 180 seconds.
10. The implementation must accept an `is_dialer` flag which specifies whether the implementation should dial or listen.

Below is a more detailed description of the test spec.

### Dialer

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

### Listener

The listener should emit all diagnostic logs to `stderr`.

1. Connect to the Redis instance.
2. Create a libp2p node as defined by the environment variables.
3. Publish the listener's address via Redis' `RPUSH` using the `listenerAddr`
   key.
4. Sleep for the duration of `test_timeout_seconds`. The test runner will kill this
   process when the dialer finishes.
5. If the timeout is hit, exit with a non-zero error code.

On error, the listener should return a non-zero exit code.

# Caching

The caching strategy is opinionated in an attempt to make things simpler and
faster. Here's how it works:

1. We cache the result of image.json in each implementation folder.
2. The cache key is derived from the hashes of the files in the implementation folder.
3. When loading from cache, if we have a cache hit, we load the image into
   docker and create the image.json file. We then call `make -o image.json` to
   allow the implementation to build any extra things from cache (e.g. JS-libp2p
   builds browser images from the same base as node). If we have a cache miss,
   we simply call `make` and build from scratch.
4. When we push the cache we use the cache-key along with the docker platform
   (arm64 vs x86_64).
