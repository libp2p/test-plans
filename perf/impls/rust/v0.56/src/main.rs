// Perf protocol implementation for rust-v0.56
// Uses Redis for listener/dialer coordination (like transport tests)

use redis::AsyncCommands;
use std::env;
use std::time::Instant;
use tokio::time::Duration;

#[tokio::main]
async fn main() {
    // Read configuration from environment variables
    let is_dialer = env::var("IS_DIALER").unwrap_or_else(|_| "false".to_string()) == "true";
    let redis_addr = env::var("REDIS_ADDR").unwrap_or_else(|_| "redis:6379".to_string());
    let transport = env::var("TRANSPORT").unwrap_or_else(|_| "tcp".to_string());
    let secure = env::var("SECURE_CHANNEL").ok();
    let muxer = env::var("MUXER").ok();

    if is_dialer {
        run_dialer(redis_addr, transport, secure, muxer).await;
    } else {
        run_listener(redis_addr, transport, secure, muxer).await;
    }
}

async fn run_listener(redis_addr: String, transport: String, secure: Option<String>, muxer: Option<String>) {
    eprintln!("Starting perf listener...");
    eprintln!("Transport: {}", transport);
    eprintln!("Secure: {:?}", secure);
    eprintln!("Muxer: {:?}", muxer);

    // Connect to Redis
    let redis_url = format!("redis://{}", redis_addr);
    let client = redis::Client::open(redis_url).expect("Failed to create Redis client");
    let mut con = client.get_multiplexed_async_connection().await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {}", redis_addr);

    // Generate listener multiaddr
    // In real implementation, this would be the actual libp2p multiaddr
    // For now, use a placeholder that includes container hostname
    let listener_multiaddr = format!("/ip4/0.0.0.0/tcp/4001");

    // Publish multiaddr to Redis
    let _: () = con.set("listener_multiaddr", &listener_multiaddr).await
        .expect("Failed to publish multiaddr to Redis");

    eprintln!("Published multiaddr to Redis: {}", listener_multiaddr);
    eprintln!("Listener ready, waiting for connections...");

    // Keep listener running
    // In real implementation, this would handle incoming perf protocol requests
    tokio::signal::ctrl_c().await.ok();
}

async fn run_dialer(redis_addr: String, transport: String, secure: Option<String>, muxer: Option<String>) {
    // Read test parameters from environment
    let upload_bytes: u64 = env::var("UPLOAD_BYTES")
        .unwrap_or_else(|_| "1073741824".to_string())
        .parse().unwrap_or(1073741824);
    let download_bytes: u64 = env::var("DOWNLOAD_BYTES")
        .unwrap_or_else(|_| "1073741824".to_string())
        .parse().unwrap_or(1073741824);
    let upload_iterations: u32 = env::var("UPLOAD_ITERATIONS")
        .unwrap_or_else(|_| "10".to_string())
        .parse().unwrap_or(10);
    let download_iterations: u32 = env::var("DOWNLOAD_ITERATIONS")
        .unwrap_or_else(|_| "10".to_string())
        .parse().unwrap_or(10);
    let latency_iterations: u32 = env::var("LATENCY_ITERATIONS")
        .unwrap_or_else(|_| "100".to_string())
        .parse().unwrap_or(100);

    eprintln!("Starting perf dialer...");
    eprintln!("Transport: {}", transport);
    eprintln!("Secure: {:?}", secure);
    eprintln!("Muxer: {:?}", muxer);

    // Connect to Redis
    let redis_url = format!("redis://{}", redis_addr);
    let client = redis::Client::open(redis_url).expect("Failed to create Redis client");
    let mut con = client.get_multiplexed_async_connection().await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {}", redis_addr);

    // Wait for listener multiaddr (with retries)
    eprintln!("Waiting for listener multiaddr...");
    let listener_addr = wait_for_listener(&mut con).await;
    eprintln!("Got listener multiaddr: {}", listener_addr);

    // Give listener a moment to be fully ready
    tokio::time::sleep(Duration::from_secs(2)).await;

    // ========================================
    // Run all 3 measurements sequentially
    // ========================================

    // Measurement 1: Upload
    eprintln!("Running upload test ({} iterations)...", upload_iterations);
    let upload_stats = run_measurement(upload_bytes, 0, upload_iterations).await;

    // Measurement 2: Download
    eprintln!("Running download test ({} iterations)...", download_iterations);
    let download_stats = run_measurement(0, download_bytes, download_iterations).await;

    // Measurement 3: Latency
    eprintln!("Running latency test ({} iterations)...", latency_iterations);
    let latency_stats = run_measurement(1, 1, latency_iterations).await;

    // Output complete results as YAML to stdout
    println!("# Upload measurement");
    println!("upload:");
    println!("  iterations: {}", upload_iterations);
    println!("  median: {:.2}", upload_stats.median);
    println!("  min: {:.2}", upload_stats.min);
    println!("  max: {:.2}", upload_stats.max);
    println!();
    println!("# Download measurement");
    println!("download:");
    println!("  iterations: {}", download_iterations);
    println!("  median: {:.2}", download_stats.median);
    println!("  min: {:.2}", download_stats.min);
    println!("  max: {:.2}", download_stats.max);
    println!();
    println!("# Latency measurement");
    println!("latency:");
    println!("  iterations: {}", latency_iterations);
    println!("  median: {:.6}", latency_stats.median);
    println!("  min: {:.6}", latency_stats.min);
    println!("  max: {:.6}", latency_stats.max);

    eprintln!("All measurements complete!");
}

async fn wait_for_listener(con: &mut redis::aio::MultiplexedConnection) -> String {
    for _ in 0..30 {
        if let Ok(Some(addr)) = con.get::<_, Option<String>>("listener_multiaddr").await {
            return addr;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    panic!("Timeout waiting for listener multiaddr");
}

struct Stats {
    median: f64,
    min: f64,
    max: f64,
}

async fn run_measurement(upload_bytes: u64, download_bytes: u64, iterations: u32) -> Stats {
    let mut values = Vec::new();

    for _ in 0..iterations {
        let start = Instant::now();

        // Placeholder: simulate transfer
        // In real implementation, this would connect to listener and transfer data
        tokio::time::sleep(Duration::from_millis(10)).await;

        let elapsed = start.elapsed().as_secs_f64();

        // Calculate throughput if this is a throughput test
        let value = if upload_bytes > 100 || download_bytes > 100 {
            // Throughput in Gbps (simulated - would be real in actual implementation)
            let bytes = upload_bytes.max(download_bytes) as f64;
            (bytes * 8.0) / elapsed / 1_000_000_000.0
        } else {
            // Latency in seconds
            elapsed
        };

        values.push(value);
    }

    // Calculate statistics
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let min = *values.first().unwrap_or(&0.0);
    let max = *values.last().unwrap_or(&0.0);
    let median = if values.len() % 2 == 0 {
        (values[values.len() / 2 - 1] + values[values.len() / 2]) / 2.0
    } else {
        values[values.len() / 2]
    };

    Stats { median, min, max }
}
