// Perf protocol implementation for rust-v0.56
// Uses Redis for listener/dialer coordination (like transport tests)

mod protocol;

use redis::AsyncCommands;
use std::env;
use std::time::Instant;
use tokio::time::Duration;

use libp2p::{
    futures::StreamExt,
    swarm::{SwarmEvent, NetworkBehaviour},
    request_response::{self, OutboundRequestId, ProtocolSupport},
    Swarm, SwarmBuilder, Multiaddr, PeerId,
};

use protocol::{PerfCodec, PerfRequest, PerfResponse, PERF_PROTOCOL};

// Perf protocol behaviour
#[derive(NetworkBehaviour)]
struct PerfBehaviour {
    request_response: request_response::Behaviour<PerfCodec>,
}

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

    // Read LISTENER_IP from environment
    let listener_ip = env::var("LISTENER_IP").expect("LISTENER_IP environment variable not set");
    eprintln!("Listener IP: {}", listener_ip);

    // Connect to Redis
    let redis_url = format!("redis://{}", redis_addr);
    let client = redis::Client::open(redis_url).expect("Failed to create Redis client");
    let mut con = client.get_multiplexed_async_connection().await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {}", redis_addr);

    // Build libp2p swarm
    let mut swarm = build_swarm(&transport, &secure, &muxer);
    let peer_id = *swarm.local_peer_id();

    eprintln!("Peer ID: {}", peer_id);

    // Construct listen multiaddr using LISTENER_IP
    let listen_multiaddr: Multiaddr = if transport == "quic-v1" {
        format!("/ip4/{}/udp/4001/quic-v1", listener_ip).parse().expect("Invalid multiaddr")
    } else {
        format!("/ip4/{}/tcp/4001", listener_ip).parse().expect("Invalid multiaddr")
    };

    eprintln!("Will listen on: {}", listen_multiaddr);

    // Start listening
    swarm.listen_on(listen_multiaddr.clone()).expect("Failed to listen");

    // Wait for listener to be ready and publish multiaddr
    loop {
        match swarm.next().await {
            Some(SwarmEvent::NewListenAddr { address, .. }) => {
                let full_multiaddr = format!("{}/p2p/{}", address, peer_id);
                eprintln!("Listening on: {}", full_multiaddr);

                // Publish to Redis
                let _: () = con.set("listener_multiaddr", full_multiaddr.clone()).await
                    .expect("Failed to publish multiaddr to Redis");

                eprintln!("Published multiaddr to Redis: {}", full_multiaddr);
                break;
            }
            _ => {}
        }
    }

    eprintln!("Listener ready, waiting for connections...");

    // Keep swarm running to handle incoming perf requests
    loop {
        if let Some(event) = swarm.next().await {
            match event {
                SwarmEvent::ConnectionEstablished { peer_id, connection_id, .. } => {
                    eprintln!("Connection established with: {} (connection: {:?})", peer_id, connection_id);
                }
                SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                    eprintln!("Connection closed with {}: {:?}", peer_id, cause);
                }
                SwarmEvent::Behaviour(PerfBehaviourEvent::RequestResponse(
                    request_response::Event::Message {
                        peer,
                        message: request_response::Message::Request {
                            request,
                            channel,
                            ..
                        }, ..
                    },
                )) => {
                    eprintln!("Received perf request from {}: send {} bytes, recv {} bytes",
                        peer, request.send_bytes, request.recv_bytes);

                    // Respond with the requested bytes
                    let response = PerfResponse {
                        bytes_sent: request.recv_bytes,  // Send what client wants to receive
                        bytes_received: request.send_bytes,  // Track what we received
                    };

                    swarm.behaviour_mut()
                        .request_response
                        .send_response(channel, response)
                        .ok();

                    eprintln!("Sent response: {} bytes", request.recv_bytes);
                }
                SwarmEvent::Behaviour(PerfBehaviourEvent::RequestResponse(
                    request_response::Event::ResponseSent { peer, .. }
                )) => {
                    eprintln!("Response sent to {}", peer);
                }
                _ => {}
            }
        }
    }
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
    let listener_addr_str = wait_for_listener(&mut con).await;
    eprintln!("Got listener multiaddr: {}", listener_addr_str);

    // Parse listener multiaddr
    let listener_addr: Multiaddr = listener_addr_str.parse().expect("Invalid multiaddr from Redis");

    // Build libp2p swarm
    let mut swarm = build_swarm(&transport, &secure, &muxer);
    eprintln!("Client peer ID: {}", swarm.local_peer_id());

    // Dial listener
    eprintln!("Dialing listener at: {}", listener_addr);
    swarm.dial(listener_addr.clone()).expect("Failed to dial");

    // Wait for connection to be established
    let connected_peer_id = loop {
        match swarm.next().await {
            Some(SwarmEvent::ConnectionEstablished { peer_id, connection_id, .. }) => {
                eprintln!("Connected to listener: {} (connection: {:?})", peer_id, connection_id);
                break peer_id;
            }
            Some(SwarmEvent::OutgoingConnectionError { error, .. }) => {
                eprintln!("Failed to connect: {:?}", error);
                std::process::exit(1);
            }
            _ => {}
        }
    };

    eprintln!("Connection established successfully");

    // ========================================
    // Run all 3 measurements sequentially
    // ========================================

    // Measurement 1: Upload
    eprintln!("Running upload test ({} iterations)...", upload_iterations);
    let upload_stats = run_measurement(&mut swarm, connected_peer_id, upload_bytes, 0, upload_iterations).await;

    // Measurement 2: Download
    eprintln!("Running download test ({} iterations)...", download_iterations);
    let download_stats = run_measurement(&mut swarm, connected_peer_id, 0, download_bytes, download_iterations).await;

    // Measurement 3: Latency
    eprintln!("Running latency test ({} iterations)...", latency_iterations);
    let latency_stats = run_measurement(&mut swarm, connected_peer_id, 1, 1, latency_iterations).await;

    // Output complete results as YAML to stdout
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
    println!();
    println!("# Download measurement");
    println!("download:");
    println!("  iterations: {}", download_iterations);
    println!("  min: {:.2}", download_stats.min);
    println!("  q1: {:.2}", download_stats.q1);
    println!("  median: {:.2}", download_stats.median);
    println!("  q3: {:.2}", download_stats.q3);
    println!("  max: {:.2}", download_stats.max);
    if !download_stats.outliers.is_empty() {
        println!("  outliers: [{}]", download_stats.outliers.iter()
            .map(|v| format!("{:.2}", v))
            .collect::<Vec<_>>()
            .join(", "));
    } else {
        println!("  outliers: []");
    }
    println!("  unit: Gbps");
    println!();
    println!("# Latency measurement");
    println!("latency:");
    println!("  iterations: {}", latency_iterations);
    println!("  min: {:.3}", latency_stats.min);
    println!("  q1: {:.3}", latency_stats.q1);
    println!("  median: {:.3}", latency_stats.median);
    println!("  q3: {:.3}", latency_stats.q3);
    println!("  max: {:.3}", latency_stats.max);
    if !latency_stats.outliers.is_empty() {
        println!("  outliers: [{}]", latency_stats.outliers.iter()
            .map(|v| format!("{:.3}", v))
            .collect::<Vec<_>>()
            .join(", "));
    } else {
        println!("  outliers: []");
    }
    println!("  unit: ms");

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
    min: f64,
    q1: f64,
    median: f64,
    q3: f64,
    max: f64,
    outliers: Vec<f64>,
}

async fn run_measurement(
    swarm: &mut Swarm<PerfBehaviour>,
    peer_id: PeerId,
    upload_bytes: u64,
    download_bytes: u64,
    iterations: u32,
) -> Stats {
    let mut values = Vec::new();

    for i in 0..iterations {
        let start = Instant::now();

        // Create perf request
        let request = PerfRequest {
            send_bytes: upload_bytes,
            recv_bytes: download_bytes,
        };

        // Send request to listener
        let request_id = swarm
            .behaviour_mut()
            .request_response
            .send_request(&peer_id, request);

        // Wait for response
        let response_result = loop {
            match swarm.next().await {
                Some(SwarmEvent::Behaviour(PerfBehaviourEvent::RequestResponse(
                    request_response::Event::Message {
                        message: request_response::Message::Response {
                            request_id: id,
                            response,
                        }, ..
                    },
                ))) if id == request_id => {
                    break Some(response);
                }
                Some(SwarmEvent::Behaviour(PerfBehaviourEvent::RequestResponse(
                    request_response::Event::OutboundFailure {
                        request_id: id,
                        error,
                        ..
                    },
                ))) if id == request_id => {
                    eprintln!("  Iteration {}/{} failed: {:?}", i + 1, iterations, error);
                    break None;
                }
                _ => {}
            }
        };

        // Skip this iteration if request failed
        if response_result.is_none() {
            continue;
        }

        let elapsed = start.elapsed().as_secs_f64();

        // Calculate throughput or latency
        let value = if upload_bytes > 100 || download_bytes > 100 {
            // Throughput in Gbps
            let bytes = upload_bytes.max(download_bytes) as f64;
            (bytes * 8.0) / elapsed / 1_000_000_000.0
        } else {
            // Latency in milliseconds
            let converted = elapsed * 1000.0;
            eprintln!("DEBUG: Latency - elapsed={:.6}s, converted={:.3}ms", elapsed, converted);
            converted
        };

        values.push(value);
    }

    if values.is_empty() {
        eprintln!("Warning: All iterations failed, using placeholder values");
        values.push(0.0);
    }

    // Sort values for percentile calculation
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let n = values.len();
    let min = values[0];
    let max = values[n - 1];

    // Calculate percentiles
    let q1 = percentile(&values, 25.0);
    let median = percentile(&values, 50.0);
    let q3 = percentile(&values, 75.0);

    // Calculate IQR and identify outliers
    let iqr = q3 - q1;
    let lower_fence = q1 - 1.5 * iqr;
    let upper_fence = q3 + 1.5 * iqr;

    let outliers: Vec<f64> = values.iter()
        .filter(|&&v| v < lower_fence || v > upper_fence)
        .copied()
        .collect();

    Stats { min, q1, median, q3, max, outliers }
}

// Helper function to calculate percentile
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

// Build libp2p swarm with specified transport, security, and muxer
fn build_swarm(transport: &str, _secure: &Option<String>, _muxer: &Option<String>) -> Swarm<PerfBehaviour> {
    let local_key = libp2p::identity::Keypair::generate_ed25519();

    // Create perf behaviour
    let perf_behaviour = || {
        let protocols = std::iter::once((PERF_PROTOCOL, ProtocolSupport::Full));
        let cfg = request_response::Config::default();

        PerfBehaviour {
            request_response: request_response::Behaviour::new(
                protocols,
                cfg,
            ),
        }
    };

    if transport == "quic-v1" {
        // QUIC transport (standalone - includes encryption and muxing)
        SwarmBuilder::with_existing_identity(local_key)
            .with_tokio()
            .with_quic()
            .with_behaviour(|_| perf_behaviour())
            .expect("Failed to create swarm")
            .build()
    } else {
        // TCP transport with noise and yamux
        SwarmBuilder::with_existing_identity(local_key)
            .with_tokio()
            .with_tcp(
                Default::default(),
                libp2p::noise::Config::new,
                libp2p::yamux::Config::default,
            )
            .expect("Failed to create TCP transport")
            .with_behaviour(|_| perf_behaviour())
            .expect("Failed to create swarm")
            .build()
    }
}
