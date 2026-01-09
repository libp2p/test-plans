# How to Write a Transport Test Application

You want to write a new transport test do you? You've come to the correct place.
This document will describe exactly how to write an application and define a
Dockerfile so that it can be run by the `transport` test in this repo.

## The Goals of These Transport Tests

The `transport` test (i.e. the test executed by the `transport/run.sh` script)
seeks to measure the following:

1. Dial success
2. Handshake latency
3. Ping latency

Currently, the test framework runs both the dialer and the listener
applications on the same host and docker network. 

### Measuring dial success

This is trivial, if the dialer successfully handshakes, then it successfully
dialed the listener. The exit status of the test reflects the success of the
dial operation. If the dial fails, then the test is marked as failed.

### Measuring the Latency

To measure the latency, we calculate the time to complete the handshake and
also record the ping latency measurement.

## Test Setup

The testing script executes the `transport` test using Docker Compose. It
generates a `docker-compose.yaml` file for each test. The `docker-compose.yaml`
file passes to the `listener` and `dialer` a set of environment variables that
they will use to know how to execute the test.

### Example Generated `docker-compose.yaml`

```yaml
name: rust-v0_56_x_rust-v0_56__quic-v1_

networks:
  transport-network:
    external: true

services:
  listener:
    image: transport-rust-v0.56
    container_name: rust-v0_56_x_rust-v0_56__quic-v1__listener
    init: true
    networks:
      - transport-network
    environment:
      - IS_DIALER=false
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=a5b50d5e
      - TRANSPORT=quic-v1
      - LISTENER_IP=0.0.0.0
      - DEBUG=false

  dialer:
    image: transport-rust-v0.56
    container_name: rust-v0_56_x_rust-v0_56__quic-v1__dialer
    depends_on:
      - listener
    networks:
      - transport-network
    environment:
      - IS_DIALER=true
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=a5b50d5e
      - TRANSPORT=quic-v1
      - LISTENER_IP=0.0.0.0
      - DEBUG=false
```

When `docker compose` is executed, it brings up the `listener` and `dialer`
docker images and attaches them to the `transport-network` that has already been
created in the "start global services" step of the test pass. There is a global
Redis server already running in the `transport-network` and its address is passed to
both services using the `REDIS_ADDR` environment variable. Both services are
assigned an IP address dynamically and both have access to the DNS server
running in the network; that is how `transport-redis` resolution happens.

## Test Execution

Typically you only need to write one application that can function both as the
`listener` and the `dialer`. The `dialer` is responsible for connecting to the
listener and running the ping protocol with the listener. 

Please note that all logging and debug messages must be send to stderr. The
stdout stream is *only* used for reporting the results in YAML format.

The typical high-level flow for any `transport` test application is as follows:

1. Your application reads the common environment variables:

   ```sh
   DEBUG=false                  # boolean value, either true or false
   IS_DIALER=true               # boolean value, either true or false
   REDIS_ADDR=transport-redis:6379   # URL and port: transport-redis:6379
   TEST_KEY=a5b50d5e            # 8-character hexidecimal string
   TRANSPORT=tcp                # transport name: tcp, quic-v2, ws, webrtc, etc
   SECURE_CHANNEL=noise         # secure channel name: noise, tls
   MUXER=yamux                  # muxer name: yamux, noise
   ```

   NOTE: The `SECURE_CHANNEL` and `MUXER` environment variables are not set when
   the `TRANSPORT` is a "standalone" transport such as "quic-v1", etc.

   NOTE: The `TEST_KEY` value is the first 8 hexidecimal characters of the sha2
   256 hash of the test name. This is used for namespacing the key(s) used when
   interacting with the global redis server for coordination.

   NOTE: The `DEBUG` value is set to true when the test was run with `--debug`.
   This is to signal to the test applications to generate verbose logging for
   debug purposes.

2. If `IS_DIALER` is true, run the `dialer` code, else, run the `listener` code
   (see below).

### `dialer` Application Flow

1. When your test application is run in `dialer` mode, there are no other
   environment variables needed.

2. Connect to the Redis server at `REDIS_ADDR` and poll it asking for the value
   associated with the `<TEST_KEY>_listener_multiaddr` key.

3. Dial the `listener` at the multiaddr you received from the Redis server.

4. Calculate the time it took to dial, connect, and complete the handshake with the `listener`.

5. Handle the ping protocol responses and record the round trip latency.

6. Print to stdout, the results in YAML format (see the section "Results
   Schema" below).

7. Exit cleanly with an exit code of 0. If there are any errors, exit with a
   non-zero exit code to signal test failure.

### `listener` Application Flow

1. When your test application is run in `listener` mode, it will be passed the
   following environment variables that are unique to the `listener`. Your
   application must read these as well:

   ```sh
   LISTENER_IP=0.0.0.0
   ```

   NOTE: The `LISTENER_IP` is somewhat historical and is always set to
   `0.0.0.0` to get the test application to bind to all interfaces. it is up to
   your application to detect the non-localhost interface your application is
   bound to so that it can properly calculate its address to send to Redis.

2. Listen on the non-localhost network interface and calculate your multiaddr.

3. Connect to the Redis server at the `REDIS_ADDR` location and set the value
   for the key `<TEST_KEY>_listener_multiaddr` to your multiaddr value.

   NOTE: The use of the `TEST_KEY` value in the key name effectively namespaces
   the key-value pair used for each test. Since we typically run multiple tests
   in parallel, this keeps the tests isolated from each other on the global
   Redis server.

4. Run the event loop so that libp2p can complete the handshake and the ping
   protocol runs.

5. The `listener` must run until it is shutdown by Docker. Don't worry about
   exiting logic. When the `dialer` exits, the `listener` container is
   automatically shut down.

## Results Schema

To report the results of the `transport` test in a way that the test scripts
understand, your test application must output the results of the handshake
latency and the ping latency in YAML format by simply printing it to stdout.
The `transport` scripts read the stdout from the `dialer` and save it into a
per-test results.yaml file for later consolidation into the global results.yaml
file for the full test run.

Below is an example of a valid results report printed to stdout:

```yaml
# Measurements from dialer
latency:
  handshake_plus_one_rtt: 5.011
  ping_rtt: 0.599
  unit: ms
```

NOTE: The `transport/lib/run-signle-test.sh` script handles adding the metadata
for the results file in each test. It writes out something like the following
and then appends the data your test application writes to stdout after it:

```yaml
test: rust-v0.56 x rust-v0.56 (quic-v1)
dialer: rust-v0.56
listener: rust-v0.56
transport: quic-v1
secureChannel: null
muxer: null
status: pass
duration: 1
```

NOTE: the `status` value of `pass` or `fail` is determined by the exit code of
your test application in `dialer` mode. If that exits with '0' then `status`
will be set to `pass` and the test will be reported as passing. Any other value
will cause `status` to be set to `fail` and the test will be reported as
failing.

