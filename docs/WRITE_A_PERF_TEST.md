# How to Write a Perf Test Implementation

This guide explains how to write a libp2p performance test implementation that works with the bash-based perf test framework.

## Overview

The perf test framework uses a **listener/dialer architecture** coordinated by Redis. Each test runs two containers:
- **Listener** - Starts a libp2p perf server and publishes its multiaddr to Redis
- **Dialer** - Reads the listener's multiaddr, connects, runs performance tests, and outputs results

## Architecture

```
     ┌─────────────┐
     │   Redis     │ ← Coordination server
     │   :6379     │
     └──────┬──────┘
            │
   ┌────────┴───────┐
   │                │
┌──▼───────────┐ ┌──▼───────────┐
│ Listener     │ │ Dialer       │
│              │ │              │
│ 1. Start     │ │ 3. Wait      │
│ 2. Publish   │ │ 4. Read      │
│    multiaddr │ │    multiaddr │
│ 5. Listen    │ │ 6. Connect   │
│ 7. Respond   │ │ 8. Measure   │
│              │ │ 9. Output    │
└──────────────┘ └──────────────┘
```

## Environment Variables

Your application receives configuration through environment variables set by the test framework.

### Common Variables (Both Listener and Dialer)

| Variable | Example | Description |
|----------|---------|-------------|
| `IS_DIALER` | `"true"` or `"false"` | Determines if running as dialer or listener |
| `REDIS_ADDR` | `"redis:6379"` | Redis server address for coordination |
| `TRANSPORT` | `"tcp"`, `"quic-v1"`, `"webtransport"` | Transport protocol to use |
| `SECURE_CHANNEL` | `"noise"`, `"tls"` (optional) | Security protocol (may be unset for standalone transports) |
| `MUXER` | `"yamux"`, `"mplex"` (optional) | Stream multiplexer (may be unset for standalone transports) |

### Listener-Only Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `LISTENER_IP` | `"10.5.0.10"` | Static IP address assigned to listener container |

### Dialer-Only Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `UPLOAD_BYTES` | `"1073741824"` | Bytes to upload per test (default: 1GB) |
| `DOWNLOAD_BYTES` | `"1073741824"` | Bytes to download per test (default: 1GB) |
| `UPLOAD_ITERATIONS` | `"10"` | Number of upload test iterations |
| `DOWNLOAD_ITERATIONS` | `"10"` | Number of download test iterations |
| `LATENCY_ITERATIONS` | `"100"` | Number of latency test iterations |
| `DURATION` | `"20"` | Duration in seconds (optional, for alternative test modes) |

## Step-by-Step Implementation

### Step 1: Determine Mode (Listener or Dialer)

```rust
// Rust example
let is_dialer = env::var("IS_DIALER").unwrap_or("false".to_string()) == "true";

if is_dialer {
    run_dialer().await;
} else {
    run_listener().await;
}
```

```go
// Go example
isDialer := os.Getenv("IS_DIALER") == "true"

if isDialer {
    runDialer()
} else {
    runListener()
}
```

```csharp
// C# example
var isDialer = Environment.GetEnvironmentVariable("IS_DIALER") == "true";

if (isDialer) {
    await RunDialer();
} else {
    await RunListener();
}
```

### Step 2: Listener Implementation

The listener must:
1. Connect to Redis
2. Start libp2p perf server
3. Publish multiaddr to Redis key `"listener_multiaddr"`
4. Keep running (wait for signals)

**Example (Rust):**
```rust
async fn run_listener(redis_addr: String) {
    // 1. Connect to Redis
    let redis_url = format!("redis://{}", redis_addr);
    let client = redis::Client::open(redis_url).expect("Failed to connect to Redis");
    let mut con = client.get_multiplexed_async_connection().await
        .expect("Failed to get Redis connection");

    // 2. Start libp2p perf server
    let host = create_libp2p_host().await;

    // 3. Construct multiaddr using LISTENER_IP from environment
    let listener_ip = env::var("LISTENER_IP").expect("LISTENER_IP not set");
    let peer_id = host.peer_id().to_string();

    // For TCP:
    let multiaddr = format!("/ip4/{}/tcp/4001/p2p/{}", listener_ip, peer_id);
    // For QUIC:
    // let multiaddr = format!("/ip4/{}/udp/4001/quic-v1/p2p/{}", listener_ip, peer_id);

    // 4. Publish multiaddr to Redis
    let _: () = con.set("listener_multiaddr", &multiaddr).await
        .expect("Failed to publish multiaddr");

    eprintln!("Listener ready at: {}", multiaddr);

    // 4. Keep running
    tokio::signal::ctrl_c().await.ok();
}
```

**Key Points:**
- Listener runs FIRST (docker-compose `depends_on`)
- Publishes to Redis key: `"listener_multiaddr"` (exact string)
- Must not exit - keep running until signaled

### Step 3: Dialer Implementation

The dialer must:
1. Connect to Redis
2. Wait for listener multiaddr from Redis
3. Connect to listener
4. Run three measurements: upload, download, latency
5. Output results as YAML to stdout
6. Exit when complete

**Example (Rust):**
```rust
async fn run_dialer(redis_addr: String) {
    // Read test parameters from environment
    let upload_bytes: u64 = env::var("UPLOAD_BYTES")
        .unwrap_or("1073741824".to_string())
        .parse().unwrap();
    let upload_iterations: u32 = env::var("UPLOAD_ITERATIONS")
        .unwrap_or("10".to_string())
        .parse().unwrap();
    // ... (similar for download and latency)

    // 1. Connect to Redis
    let redis_url = format!("redis://{}", redis_addr);
    let client = redis::Client::open(redis_url).expect("Failed to connect to Redis");
    let mut con = client.get_multiplexed_async_connection().await.expect("Failed");

    // 2. Wait for listener multiaddr (with retries)
    let listener_addr = wait_for_listener(&mut con).await;

    // 3. Connect to listener
    let host = create_libp2p_host().await;
    let peer_id = connect_to_listener(&host, &listener_addr).await;

    // 4. Run measurements
    let upload_stats = run_measurement(host, peer_id, upload_bytes, 0, upload_iterations).await;
    let download_stats = run_measurement(host, peer_id, 0, download_bytes, download_iterations).await;
    let latency_stats = run_measurement(host, peer_id, 1, 1, latency_iterations).await;

    // 5. Output results (see Output Format section)
    output_results(upload_stats, download_stats, latency_stats);

    // 6. Exit (dialer completes, triggering container shutdown)
}
```

**Waiting for Listener (with retries):**
```rust
async fn wait_for_listener(con: &mut redis::aio::MultiplexedConnection) -> String {
    for _ in 0..30 {  // 30 retries = 15 seconds
        if let Ok(Some(addr)) = con.get::<_, Option<String>>("listener_multiaddr").await {
            return addr;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    panic!("Timeout waiting for listener multiaddr");
}
```

### Step 4: Run Measurements

Each measurement:
1. Runs multiple iterations
2. Measures throughput (Gbps) or latency (milliseconds)
3. Calculates box plot statistics: min, Q1, median, Q3, max, outliers

**Example:**
```rust
async fn run_measurement(upload_bytes: u64, download_bytes: u64, iterations: u32) -> Stats {
    let mut values = Vec::new();

    for _ in 0..iterations {
        let start = Instant::now();

        // Run actual perf protocol transfer
        // For upload: send upload_bytes to peer
        // For download: receive download_bytes from peer
        // For latency: send 1 byte, receive 1 byte
        let result = perf_send(peer_id, upload_bytes, download_bytes).await;

        let elapsed = start.elapsed().as_secs_f64();

        // Calculate throughput (Gbps) or latency (milliseconds)
        let value = if upload_bytes > 100 || download_bytes > 100 {
            let bytes = upload_bytes.max(download_bytes) as f64;
            (bytes * 8.0) / elapsed / 1_000_000_000.0  // Gbps
        } else {
            elapsed * 1000.0  // Latency in milliseconds
        };

        values.push(value);
    }

    // Calculate box plot statistics
    calculate_stats(values)
}
```

**Three Measurements to Run:**
1. **Upload** - Send `UPLOAD_BYTES` bytes, measure throughput
2. **Download** - Receive `DOWNLOAD_BYTES` bytes, measure throughput
3. **Latency** - Send/receive minimal data (1 byte each), measure round-trip time

### Step 5: Calculate Box Plot Statistics

Calculate the 5-number summary plus outliers:
```rust
fn calculate_stats(mut values: Vec<f64>) -> Stats {
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let n = values.len();
    let min = values[0];
    let max = values[n - 1];

    // Percentiles
    let q1 = percentile(&values, 25.0);
    let median = percentile(&values, 50.0);
    let q3 = percentile(&values, 75.0);

    // Outliers using IQR method
    let iqr = q3 - q1;
    let lower_fence = q1 - 1.5 * iqr;
    let upper_fence = q3 + 1.5 * iqr;

    let outliers: Vec<f64> = values.iter()
        .filter(|&&v| v < lower_fence || v > upper_fence)
        .copied()
        .collect();

    Stats { min, q1, median, q3, max, outliers }
}

fn percentile(sorted_values: &[f64], p: f64) -> f64 {
    let n = sorted_values.len();
    let index = (p / 100.0) * (n - 1) as f64;
    let lower = index.floor() as usize;
    let upper = index.ceil() as usize;

    if lower == upper {
        sorted_values[lower]
    } else {
        let weight = index - lower as f64;
        sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight
    }
}
```

### Step 6: Output Results (CRITICAL)

**IMPORTANT:**
- Output to **stdout** (not stderr)
- Format: **YAML** (not JSON)
- Logging/debug: Use **stderr**

**Required YAML Structure:**
```yaml
# Upload measurement
upload:
  iterations: 10
  min: 7.92
  q1: 8.15
  median: 8.45
  q3: 8.78
  max: 9.13
  outliers: [7.12, 9.87]
  unit: Gbps

# Download measurement
download:
  iterations: 10
  min: 8.67
  q1: 8.89
  median: 9.12
  q3: 9.34
  max: 9.58
  outliers: []
  unit: Gbps

# Latency measurement
latency:
  iterations: 100
  min: 11.234
  q1: 11.897
  median: 12.456
  q3: 13.012
  max: 15.678
  outliers: [10.123, 18.456]
  unit: ms
```

**Rust Example:**
```rust
// Upload results
println!("# Upload measurement");
println!("upload:");
println!("  iterations: {}", upload_iterations);
println!("  min: {:.2}", upload_stats.min);
println!("  q1: {:.2}", upload_stats.q1);
println!("  median: {:.2}", upload_stats.median);
println!("  q3: {:.2}", upload_stats.q3);
println!("  max: {:.2}", upload_stats.max);
if !upload_stats.outliers.is_empty() {
    println!("  outliers: [{}]", upload_stats.outliers.iter()
        .map(|v| format!("{:.2}", v))
        .collect::<Vec<_>>()
        .join(", "));
} else {
    println!("  outliers: []");
}
println!("  unit: Gbps");
println!();  // Blank line between sections

// Repeat for download and latency...
```

**C# Example:**
```csharp
// Upload results
Console.WriteLine("# Upload measurement");
Console.WriteLine("upload:");
Console.WriteLine($"  iterations: {uploadIterations}");
Console.WriteLine($"  min: {uploadStats.Min:F2}");
Console.WriteLine($"  q1: {uploadStats.Q1:F2}");
Console.WriteLine($"  median: {uploadStats.Median:F2}");
Console.WriteLine($"  q3: {uploadStats.Q3:F2}");
Console.WriteLine($"  max: {uploadStats.Max:F2}");
if (uploadStats.Outliers.Any()) {
    var outliers = string.Join(", ", uploadStats.Outliers.Select(v => v.ToString("F2")));
    Console.WriteLine($"  outliers: [{outliers}]");
} else {
    Console.WriteLine("  outliers: []");
}
Console.WriteLine("  unit: Gbps");
Console.WriteLine();

// Repeat for download and latency...
```

**Precision Requirements:**
- Throughput (upload/download): 2 decimal places (e.g., `8.45`)
- Latency: 3 decimal places (e.g., `12.456`)

## Complete Implementation Checklist

### ✅ Listener Requirements

1. Read environment variables:
   - `IS_DIALER` (must be "false")
   - `REDIS_ADDR`
   - `TRANSPORT`, `SECURE_CHANNEL`, `MUXER`

2. Connect to Redis at `REDIS_ADDR`

3. Create libp2p host with appropriate transport/security/muxer

4. Get listening multiaddr (e.g., `/ip4/0.0.0.0/tcp/4001/p2p/<peer-id>`)

5. Publish multiaddr to Redis:
   ```
   Key: "listener_multiaddr"
   Value: <full multiaddr string with DNS hostname>
   ```

   **CRITICAL:** Use the `LISTENER_IP` environment variable for the IP address
   - Read from environment: `LISTENER_IP` (e.g., "10.5.0.10")
   - For TCP: `/ip4/<LISTENER_IP>/tcp/4001/p2p/<peer-id>`
   - For QUIC: `/ip4/<LISTENER_IP>/udp/4001/quic-v1/p2p/<peer-id>`
   - Do NOT use `0.0.0.0` (not routable from dialer)

6. Keep running (don't exit)

7. Handle incoming perf protocol requests

### ✅ Dialer Requirements

1. Read environment variables:
   - `IS_DIALER` (must be "true")
   - `REDIS_ADDR`
   - `TRANSPORT`, `SECURE_CHANNEL`, `MUXER`
   - `UPLOAD_BYTES`, `DOWNLOAD_BYTES`
   - `UPLOAD_ITERATIONS`, `DOWNLOAD_ITERATIONS`, `LATENCY_ITERATIONS`

2. Connect to Redis at `REDIS_ADDR`

3. Wait for listener multiaddr from Redis key `"listener_multiaddr"`
   - Retry with backoff (recommended: 30 retries × 500ms = 15 seconds)
   - Fail if timeout

4. Create libp2p host

5. Connect to listener using multiaddr

6. Run three measurements **sequentially**:
   - Upload test (`UPLOAD_ITERATIONS` times)
   - Download test (`DOWNLOAD_ITERATIONS` times)
   - Latency test (`LATENCY_ITERATIONS` times)

7. Calculate box plot statistics for each measurement:
   - min, q1, median, q3, max, outliers

8. Output results as YAML to **stdout**

9. Exit with code 0 on success, non-zero on failure

## Logging Best Practices

**Use stderr for logging:**
```rust
eprintln!("Starting perf dialer...");
eprintln!("Connected to listener");
```

**Use stdout ONLY for results:**
```rust
println!("upload:");
println!("  median: {:.2}", median);
```

**Why?** The test framework extracts YAML from stdout. Logging on stdout corrupts the results.

## Docker Compose Flow

The test framework creates a docker-compose file like this:

```yaml
services:
  redis:
    image: redis:7-alpine

  listener:
    image: perf-<impl-id>
    depends_on: [redis]
    environment:
      - IS_DIALER=false
      - REDIS_ADDR=redis:6379
      - TRANSPORT=tcp
      - SECURE_CHANNEL=noise
      - MUXER=yamux

  dialer:
    image: perf-<impl-id>
    depends_on: [redis, listener]
    environment:
      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
      - TRANSPORT=tcp
      - UPLOAD_BYTES=1073741824
      - DOWNLOAD_BYTES=1073741824
      - UPLOAD_ITERATIONS=10
      - DOWNLOAD_ITERATIONS=10
      - LATENCY_ITERATIONS=100
      - SECURE_CHANNEL=noise
      - MUXER=yamux
```

**Execution:**
1. Redis starts
2. Listener starts, publishes multiaddr, keeps running
3. Dialer starts, reads multiaddr, connects, runs tests, outputs results, exits
4. Framework extracts YAML from dialer logs
5. Containers are cleaned up

## Common Pitfalls

### ❌ Wrong: Output to stderr
```rust
eprintln!("upload:");  // This goes to logs, not results!
```

### ✅ Correct: Output to stdout
```rust
println!("upload:");  // This goes to results
```

### ❌ Wrong: JSON output
```rust
println!(r#"{{"median": 8.45}}"#);  // Framework expects YAML!
```

### ✅ Correct: YAML output
```rust
println!("  median: 8.45");
```

### ❌ Wrong: Listener exits too early
```rust
// Listener publishes then exits
con.set("listener_multiaddr", &addr).await;
// EXIT - dialer won't be able to connect!
```

### ✅ Correct: Listener keeps running
```rust
con.set("listener_multiaddr", &addr).await;
tokio::signal::ctrl_c().await.ok();  // Wait forever
```

### ❌ Wrong: Dialer doesn't wait for listener
```rust
// Connect immediately without checking Redis
dial(listener_addr);  // listener_addr might not be ready!
```

### ✅ Correct: Dialer waits for Redis
```rust
let listener_addr = wait_for_listener(&mut con).await;  // Retry loop
dial(listener_addr);
```

## Testing Your Implementation

### 1. Build the Docker image
```bash
cd perf
bash scripts/build-images.sh "your-impl-id" "true"
```

### 2. Run a single test
```bash
./run_tests.sh --test-select "your-impl-id" --iterations 5 --debug
```

### 3. Check the logs
```bash
cat /srv/cache/test-runs/perf-*/logs/<test-name>.log
```

Look for:
- ✅ Listener publishes multiaddr
- ✅ Dialer reads multiaddr
- ✅ Connection successful
- ✅ Measurements complete
- ✅ YAML output on stdout

### 4. Verify results
```bash
cat /srv/cache/test-runs/perf-*/results.yaml
```

Should contain your test with all measurements.

## Reference Implementations

**Working examples in this repository:**
- **Rust:** `perf/impls/rust/v0.56/src/main.rs` - Complete implementation
- **Go:** `perf/impls/go/v0.45/main.go` - Complete implementation
- **JavaScript:** `perf/impls/js/v3.x/index.js` - Complete implementation

## Quick Checklist

Before submitting your implementation, verify:

- [ ] Reads `IS_DIALER` environment variable
- [ ] Connects to Redis at `REDIS_ADDR`
- [ ] Listener publishes to key `"listener_multiaddr"`
- [ ] Listener keeps running (doesn't exit)
- [ ] Dialer waits for listener multiaddr with retries
- [ ] Dialer reads all test parameters from environment
- [ ] Runs 3 measurements: upload, download, latency
- [ ] Calculates box plot stats: min, q1, median, q3, max, outliers
- [ ] Outputs YAML to stdout (not stderr)
- [ ] Uses correct precision: 2 decimals for Gbps, 6 for seconds
- [ ] All logging goes to stderr
- [ ] Dialer exits after outputting results
- [ ] Docker build creates working image
- [ ] Test runs successfully with `./run_tests.sh`

## Troubleshooting

**"Timeout waiting for listener multiaddr"**
- Listener not publishing to Redis
- Check Redis connection in listener
- Verify key name is exactly `"listener_multiaddr"`

**"No YAML output in results"**
- Check you're using `println!()` not `eprintln!()`
- Verify YAML format (use spaces, not tabs)
- Check indentation is exactly 2 spaces

**"Connection failed"**
- Listener multiaddr might be incorrect
- Check transport/security/muxer configuration matches
- Verify libp2p host setup

**"Docker build fails"**
- Check Dockerfile syntax
- Ensure all dependencies are installed
- Verify binary is copied to correct location
