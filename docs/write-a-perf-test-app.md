# How to Write a Perf Test Application

You want to write a new perf test do you? You've come to the correct place.
This document will describe exactly how to write an application and define a
Dockerfile so that it can be run by the `perf` test in this repo.

## The Goals of These Perf Tests

The `perf` test (i.e. the test executed by the `perf/run.sh` script) seeks to
measure the following:

1. Upload throughput
2. Download throughput
3. Connection latency

Currently, the test framework runs both the dialer and the listener
applications on the same host and docker network. This seems ridiculous on its
face; what good is it to measure throughput through a virtual network link that
just runs at very close to system RAM/bus speed? Considering that we also
typically run baseline tests that measure raw quic, TCP, and TLS throughput,
what we are measuring is the overhead of the tested application. The primary
use case is to measure the overhead that libp2p introduces. Running these tests
in such a consistent and controlled way, on a single host, gives us the purest
measurement of the libp2p overhead and is a good source of data to drive
ongoing optimization work. In the future we will support using remote hosts via
Docker swarm, but that won't yield better results unless we are trying to
measure the libp2p overhead specifically related to network retries, dropped
packets, and other situations that happen over real network links but never
happen in a Docker network.

### Measuring Upload and Download Throughput

To measure the upload and download throughput, the test application receives
through environment variables (See Example Generated `docker-compose.yaml`
below), the amount of data to upload/download as well as the number of
iterations to repeat the test. The default amount of data is 1,073,741,824
bytes (i.e. 1 GiB or 1,024 * 1,024 * 1,024 bytes). The default number of
iterations is 10. Each iteration the dialer measures the throughput by sending
or receiving the data and timing it and recording the times.

### Measuring the Latency

To measure the latency, we run the same code as the upload/download tests,
however we only send and receive 1 byte. This effectively measures the round
trip time. The default number of iterations for a latency test is 100.

## Test Setup

The testing script executes the `perf` test using Docker Compose. It generates
a `docker-compose.yaml` file for each test that creates a single network named
`perf-network` and two services, one named `listener` and another named
`dialer`. The `docker-compose.yaml` file passes to the `listener` and `dialer`
a set of environment variables that they will use to know how to execute the
test.

### Example Generated `docker-compose.yaml`

```yaml
name: rust-v0_56_x_rust-v0_56__quic-v1_

networks:
  perf-network:
    external: true

services:
  listener:
    image: perf-rust-v0.56
    container_name: rust-v0_56_x_rust-v0_56__quic-v1__listener
    init: true
    networks:
      - perf-network
    environment:
      - IS_DIALER=false
      - REDIS_ADDR=perf-redis:6379
      - TEST_KEY=a5b50d5e
      - TRANSPORT=quic-v1
      - LISTENER_IP=0.0.0.0

  dialer:
    image: perf-rust-v0.56
    container_name: rust-v0_56_x_rust-v0_56__quic-v1__dialer
    depends_on:
      - listener
    networks:
      - perf-network
    environment:
      - IS_DIALER=true
      - REDIS_ADDR=perf-redis:6379
      - TEST_KEY=a5b50d5e
      - TRANSPORT=quic-v1
      - UPLOAD_BYTES=1073741824
      - DOWNLOAD_BYTES=1073741824
      - UPLOAD_ITERATIONS=null
      - DOWNLOAD_ITERATIONS=null
      - LATENCY_ITERATIONS=100
      - DURATION=20
```

When `docker compose` is executed, it brings up the `listener` and `dialer`
docker images and attaches them to the `perf-network` that has already been
created in the "start global services" step of the test pass. There is a global
Redis server already running in the `perf-network` and its address is passed to
both services using the `REDIS_ADDR` environment variable. Both services are
assigned an IP address dynamically and both have access to the DNS server
running in the network; that is how `perf-redis` resolution happens.

## Test Execution

Typically you only need to write one application that can function both as the
`listener` and the `dialer`. The `dialer` is respnosible for connecting to the
listener and sending a "Perf Request" to the listener. Each application gets to
define what a "Perf Request" looks like. In the case of the `rust-v0.56` test
application, it uses a custom request-response protocol to do the download and
upload tests. If it is an upload test, it sends the request with an
`UPLOAD_BYTES` amount of data and calculates the time between sending the
request and receiving a response. If it is a download test, it send the request
asking for `DOWNLOAD_BYTES` worth of data from the `listener` and the
`listener` response comes back with `DOWNLOAD_BYTES` worth of data in it.
Again, the dialer calculates the time between making the download "Perf Request"
and receiving the reply.

Please note that all logging and debug messages must be send to stderr. The
stdout stream is *only* used for reporting the results in YAML format.

The typical high-level flow for any `perf` test application is as follows:

1. Your application reads the common environment variables:

   ```sh
   DEBUG=false                  # boolean value, either true or false
   IS_DIALER=true               # boolean value, either true or false
   REDIS_ADDR=perf-redis:6379   # URL and port: perf-redis:6379
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

1. When your test application is run in `dialer` mode, it will be passed the
   following environment variables that are unique to the `dialer`. Your
   application must read these as well:

   ```sh
   UPLOAD_BYTES=1073741824
   DOWNLOAD_BYTES=1073741824
   UPLOAD_ITERATIONS=10
   DOWNLOAD_ITERATIONS=10
   LATENCY_ITERATIONS=100
   ```

2. Connect to the Redis server at `REDIS_ADDR` and poll it asking for the value
   associated with the `<TEST_KEY>_listener_multiaddr` key.

3. Dial the `listener` at the multiaddr you received from the Redis server.

4. Run the upload test with `UPLOAD_ITERATIONS` number of iterations, timing
   each iteration.

5. Run the download test with `DOWNLOAD_ITERATIONS` number of iterations,
   timing each iteration.

6. Run the latency test with `LATENCY_ITERATIONS` number of iterations, timing
   each iteration.

7. For the upload and download tests, calculate the minimum measured value, the
   maximum measured value, the Q1 (25th percentile), the median, and the Q3
   (75th percentile). Also calculate which samples are outliers by first
   calculating the inter-quartile range (i.e. Q3 - Q1) and then filtering the
   samples to see if any are less than (Q1 - 1.5 * IQR) or greater than (Q3 +
   1.5 * IQR).

8. Print to stdout, the results in YAML format (see the section "Results
   Schema" below).

9. Exit cleanly with an exit code of 0. If there are any errors, exit with a
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

4. Wait until you receive a "Perf Request" from the dialer. If it is an upload
   test, the "Perf Request" will contain `UPLOAD_BYTES` of data. If it is a
   download test, the "Perf Request" will contain the amount of data the `dialer`
   wants you to send back in the reply. If it is a latency test, the "Perf
   Request" will contain 1 byte of upload data and will request 1 byte of
   download data.

5. Send the reply back with the requested amount of download data.

6. The `listener` must run until it is shutdown by Docker. Don't worry about
   exiting logic. When the `dialer` exits, the `listener` container is
   automatically shut down.

## Results Schema

To report the results of the `perf` test in a way that the test scripts
understand, your test application must output the results of the download,
upload, and latency tests in YAML format by simply printing it to stdout. The
`perf` scripts read the stdout from the `dialer` and save it into a per-test
results.yaml file for later consolidation into the global results.yaml file for
the full test run.

Below is an example of a valid results report printed to stdout:

```yaml
# Measurements from dialer
upload:
  iterations: 10
  min: 2.04
  q1: 2.05
  median: 2.06
  q3: 2.06
  max: 2.07
  outliers: [2.02]
  samples: [2.02, 2.04, 2.05, 2.05, 2.05, 2.06, 2.06, 2.06, 2.06, 2.07]
  unit: Gbps
download:
  iterations: 10
  min: 2.05
  q1: 2.06
  median: 2.06
  q3: 2.07
  max: 2.08
  outliers: []
  samples: [2.05, 2.05, 2.06, 2.06, 2.06, 2.06, 2.07, 2.07, 2.08, 2.08]
  unit: Gbps
latency:
  iterations: 100
  min: 0.523
  q1: 0.609
  median: 0.634
  q3: 0.671
  max: 0.754
  outliers: [0.473, 0.784, 0.803]
  samples: [0.473, 0.523, 0.551, 0.572, 0.576, 0.577, 0.581, 0.584, 0.589, 0.590, 0.590, 0.592, 0.593, 0.593, 0.594, 0.595, 0.598, 0.598, 0.602, 0.603, 0.604, 0.606, 0.606, 0.607, 0.607, 0.610, 0.610, 0.611, 0.611, 0.612, 0.614, 0.615, 0.616, 0.616, 0.617, 0.618, 0.619, 0.619, 0.621, 0.623, 0.625, 0.625, 0.625, 0.625, 0.626, 0.626, 0.627, 0.627, 0.629, 0.633, 0.635, 0.635, 0.636, 0.637, 0.638, 0.639, 0.640, 0.640, 0.640, 0.641, 0.645, 0.647, 0.647, 0.651, 0.651, 0.651, 0.654, 0.654, 0.660, 0.660, 0.660, 0.661, 0.667, 0.667, 0.670, 0.673, 0.674, 0.676, 0.677, 0.681, 0.684, 0.687, 0.690, 0.691, 0.692, 0.695, 0.695, 0.699, 0.700, 0.704, 0.707, 0.709, 0.714, 0.714, 0.720, 0.733, 0.740, 0.754, 0.784, 0.803]
  unit: ms
```

The only thing in here that has not been previous documented is the reporting
of the raw samples. Since the results are calculated values, it is important to
also report the raw samples so that the results may be checked and verified
independently.

NOTE: The `perf/lib/run-signle-test.sh` script handles adding the metadata for
the results file in each test. It writes out something like the following and
then appends the data your test application writes to stdout after it:

```yaml
test: rust-v0.56 x rust-v0.56 (quic-v1)
dialer: rust-v0.56
listener: rust-v0.56
transport: quic-v1
secureChannel: null
muxer: null
status: pass
```

NOTE: the `status` value of `pass` or `fail` is determined by the exit code of
your test application in `dialer` mode. If that exits with '0' then `status`
will be set to `pass` and the test will be reported as passing. Any other value
will cause `status` to be set to `fail` and the test will be reported as
failing.

