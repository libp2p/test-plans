// Perf protocol implementation for rust-v0.56

mod protocol;

use anyhow::{bail, Context, Result};
use libp2p::{
    futures::StreamExt,
    identity::Keypair,
    Multiaddr,
    noise,
    PeerId,
    request_response::{self, ProtocolSupport},
    swarm,
    Swarm,
    tcp,
    tls,
    yamux,
};
use libp2p_mplex as mplex;
use libp2p_webrtc as webrtc;
use protocol::{PerfCodec, PerfRequest, PerfResponse, PERF_PROTOCOL};
use redis::AsyncCommands;
use std::{env, str, time::Instant};
use strum::{Display, EnumString};
use tokio::time::Duration;

#[tokio::main]
async fn main() -> Result<()> {
    // Read configuration from environment variables
    
    // optional, defaults to false
    let debug = env::var("DEBUG").ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(false);

    // required, ex. "true" or "false"
    let is_dialer = env::var("IS_DIALER")
        .context("IS_DIALER environment variable is not set")?
        .parse::<bool>()
        .context("invalid value for IS_DIALER environment variable")?;

    // required, ex. "redis:6379"
    let redis_addr = env::var("REDIS_ADDR")
        .context("REDIS_ADDR environment variable is not set")
        .map(|addr| format!("redis://{addr}"))?;

    // required, ex. "a1b2c3d4"
    let test_key = env::var("TEST_KEY").context("TEST_KEY environment variable is not set")?;

    // required, ex. "tcp", "quic-v1", "webrtc-direct", "ws", "webtransport"
    let transport: Transport = env::var("TRANSPORT")
        .context("TRANSPORT environment variable is not set")?
        .parse()
        .context("invalid value for TRANSPORT environment variable")?;

    // required, ex. "noise", "tls"
    let secure_channel: Option<SecureChannel> = env::var("SECURE_CHANNEL").ok()
        .and_then(|sc| sc.parse().ok());

    // required, ex. "mplex", "yamux"
    let muxer: Option<Muxer> = env::var("MUXER").ok()
        .and_then(|m| m.parse().ok());

    eprintln!("DEBUG: {debug}");
    eprintln!("IS_DIALER: {is_dialer}");
    eprintln!("REDIS_ADDR: {redis_addr}");
    eprintln!("TEST_KEY: {test_key}");
    eprintln!("TRANSPORT: {transport}");
    eprintln!("SECURE_CHANNEL: {:?}", secure_channel);
    eprintln!("MUXER: {:?}", muxer);

    if is_dialer {
        run_dialer(redis_addr, test_key, transport, secure_channel, muxer, debug).await
    } else {
        run_listener(redis_addr, test_key, transport, secure_channel, muxer, debug).await
    }
}

async fn run_listener(
    redis_addr: String,
    test_key: String,
    transport: Transport,
    secure_channel: Option<SecureChannel>,
    muxer: Option<Muxer>,
    debug: bool,
) -> Result<()> {

    // optional, defaults to "0.0.0.0"
    let listener_ip = env::var("LISTENER_IP").unwrap_or("0.0.0.0".to_string());

    eprintln!("Starting perf listener...");
    eprintln!("LISTENER_IP: {listener_ip}");

    // Connect to Redis
    eprintln!("Connecting to Redis at: {redis_addr}");
    let client = redis::Client::open(redis_addr.clone()).expect("Failed to create Redis client");
    let mut con = client
        .get_multiplexed_async_connection()
        .await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {redis_addr}");

    // Build libp2p swarm
    let (mut swarm, multiaddr) = build_swarm(
        Some(listener_ip),
        transport,
        secure_channel,
        muxer,
        build_behaviour
    ).await?;

    // get peer id and multiaddr to listen on
    let peer_id = *swarm.local_peer_id();
    let listener_multiaddr = match multiaddr {
        Some(addr) => addr,
        None => bail!("failed to build listener multiaddr")
    };

    eprintln!("Peer ID: {peer_id}");
    eprintln!("Will listen on: {listener_multiaddr}");

    // Start listening
    let id = swarm
        .listen_on(listener_multiaddr.clone())
        .expect("Failed to listen");

    // Wait for listener to be ready and publish multiaddr
    loop {
        if let Some(swarm::SwarmEvent::NewListenAddr {
            listener_id,
            address,
        }) = swarm.next().await
        {
            eprintln!(
                "Listener_id: {listener_id}, address: {}",
                address.to_string()
            );
            if address.to_string().contains("127.0.0.1") {
                eprintln!("Skipping localhost address");
                continue;
            }
            if listener_id == id {
                let full_multiaddr = format!("{address}/p2p/{peer_id}");
                eprintln!("Listening on: {full_multiaddr}");

                // Publish to Redis with TEST_KEY namespacing
                let listener_addr_key = format!("{test_key}_listener_multiaddr");
                let _: () = con
                    .set(&listener_addr_key, full_multiaddr.clone())
                    .await
                    .expect(&format!(
                        "Failed to publish multiaddr to Redis (key: {listener_addr_key})"
                    ));

                eprintln!("Published multiaddr to Redis (key: {listener_addr_key})");
                break;
            }
        }
    }

    eprintln!("Listener ready, waiting for connections...");

    // Keep swarm running to handle incoming perf requests
    loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id,
                    connection_id,
                    ..
                } => {
                    eprintln!(
                        "Connection established with: {peer_id} (connection: {connection_id:?})",
                    );
                }

                swarm::SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                    eprintln!("Connection closed with {peer_id}: {cause:?}");
                }

                swarm::SwarmEvent::Behaviour(BehaviourEvent::RequestResponse(
                    request_response::Event::Message {
                        peer,
                        message:
                            request_response::Message::Request {
                                request, channel, ..
                            },
                        ..
                    },
                )) => {
                    eprintln!(
                        "Received perf request from {}: send {} bytes, recv {} bytes",
                        peer, request.send_bytes, request.recv_bytes
                    );

                    // Respond with the requested bytes
                    let response = PerfResponse {
                        bytes_sent: request.recv_bytes, // Send what client wants to receive
                        _bytes_received: request.send_bytes, // Track what we received
                    };

                    swarm
                        .behaviour_mut()
                        .request_response
                        .send_response(channel, response)
                        .ok();

                    eprintln!("Sent response: {} bytes", request.recv_bytes);
                }

                swarm::SwarmEvent::Behaviour(BehaviourEvent::RequestResponse(
                    request_response::Event::ResponseSent { peer, .. },
                )) => {
                    eprintln!("Response sent to {}", peer);
                }

                other => {
                    if debug {
                        eprintln!("{other:?}")
                    }
                }
            }
        }
    }
}

async fn run_dialer(
    redis_addr: String,
    test_key: String,
    transport: Transport,
    secure_channel: Option<SecureChannel>,
    muxer: Option<Muxer>,
    debug: bool,
) -> Result<()> {

    // optional, defaults to 1 GiB (i.e. 1073741824 bytes)
    let upload_bytes: u64 = env::var("UPLOAD_BYTES").ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1073741824);

    // optional, defaults to 1 GiB (i.e. 1073741824 bytes)
    let download_bytes: u64 = env::var("DOWNLOAD_BYTES").ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1073741824);
   
    // optional, defaults to 10
    let upload_iterations: u32 = env::var("UPLOAD_ITERATIONS").ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10);

    // optional, defaults to 10
    let download_iterations: u32 = env::var("DOWNLOAD_ITERATIONS").ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10);

    // optional, defaults to 100
    let latency_iterations: u32 = env::var("LATENCY_ITERATIONS").ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(100);

    eprintln!("Starting perf dialer...");
    eprintln!("UPLOAD_BYTES: {upload_bytes}");
    eprintln!("DOWNLOAD_BYTES: {download_bytes}");
    eprintln!("UPLOAD_ITERATIONS: {upload_iterations}");
    eprintln!("DOWNLOAD_ITERATIONS: {download_iterations}");
    eprintln!("LATENCY_ITERATIONS: {latency_iterations}");

    // Connect to Redis
    eprintln!("Connecting to Redis at: {redis_addr}");
    let client = redis::Client::open(redis_addr.clone()).expect("Failed to create Redis client");
    let mut con = client
        .get_multiplexed_async_connection()
        .await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {redis_addr}");

    // Wait for listener multiaddr (with retries)
    let listener_addr = wait_for_listener(&mut con, &test_key).await?;

    // Build libp2p swarm
    let (mut swarm, _) = build_swarm(
        None,
        transport,
        secure_channel,
        muxer,
        build_behaviour
    ).await?;

    // get our peer id
    let peer_id = *swarm.local_peer_id();
    eprintln!("Peer ID: {peer_id}");

    // Dial listener
    eprintln!("Dialing listener at: {listener_addr}");
    swarm.dial(listener_addr.clone()).expect("Failed to dial");

    // Wait for connection to be established
    let connected_peer_id = loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id,
                    connection_id,
                    ..
                } => {
                    eprintln!(
                        "Connected to listener: {peer_id} (connection: {connection_id:?})"
                    );
                    break peer_id;
                }
                swarm::SwarmEvent::OutgoingConnectionError { error, .. } => {
                    eprintln!("Failed to connect: {error:?}");
                    std::process::exit(1);
                }
                other => {
                    if debug {
                        eprintln!("{other:?}");
                    }
                }
            }
        }
    };

    eprintln!("Connection established successfully");

    // ========================================
    // Run all 3 measurements sequentially
    // ========================================

    // Measurement 1: Upload
    eprintln!("Running upload test ({} iterations)...", upload_iterations);
    let upload_stats = run_measurement(
        &mut swarm,
        connected_peer_id,
        upload_bytes,
        0,
        upload_iterations,
        debug,
    )
    .await?;

    // Measurement 2: Download
    eprintln!(
        "Running download test ({} iterations)...",
        download_iterations
    );
    let download_stats = run_measurement(
        &mut swarm,
        connected_peer_id,
        0,
        download_bytes,
        download_iterations,
        debug,
    )
    .await?;

    // Measurement 3: Latency
    eprintln!(
        "Running latency test ({} iterations)...",
        latency_iterations
    );
    let latency_stats =
        run_measurement(&mut swarm, connected_peer_id, 1, 1, latency_iterations, debug).await?;

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
        println!(
            "  outliers: [{}]",
            upload_stats
                .outliers
                .iter()
                .map(|v| format!("{:.2}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  outliers: []");
    }
    if !upload_stats.samples.is_empty() {
        println!(
            "  samples: [{}]",
            upload_stats
                .samples
                .iter()
                .map(|v| format!("{:.2}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  samples: []");
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
        println!(
            "  outliers: [{}]",
            download_stats
                .outliers
                .iter()
                .map(|v| format!("{:.2}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  outliers: []");
    }
    if !download_stats.samples.is_empty() {
        println!(
            "  samples: [{}]",
            download_stats
                .samples
                .iter()
                .map(|v| format!("{:.2}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  samples: []");
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
        println!(
            "  outliers: [{}]",
            latency_stats
                .outliers
                .iter()
                .map(|v| format!("{:.3}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  outliers: []");
    }
    if !latency_stats.samples.is_empty() {
        println!(
            "  samples: [{}]",
            latency_stats
                .samples
                .iter()
                .map(|v| format!("{:.3}", v))
                .collect::<Vec<_>>()
                .join(", ")
        );
    } else {
        println!("  samples: []");
    }
    println!("  unit: ms");

    eprintln!("All measurements complete!");
    Ok(())
}

async fn wait_for_listener(con: &mut redis::aio::MultiplexedConnection, test_key: &str) -> Result<Multiaddr> {
    let listener_addr_key = format!("{}_listener_multiaddr", test_key);
    eprintln!(
        "Waiting for listener multiaddr from Redis (key: {})...",
        listener_addr_key
    );
    // retries 30 times, waiting a total of 15 seconds before panicking
    for _ in 0..30 {
        if let Ok(Some(addr)) = con.get::<_, Option<String>>(&listener_addr_key).await {
            eprintln!("Got listener multiaddr (key: {})", listener_addr_key);
            return addr.parse().context("Invalid listener multiaddr from Redis");
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    panic!(
        "Timeout waiting for listener multiaddr (key: {})",
        listener_addr_key
    );
}

struct Stats {
    min: f64,
    q1: f64,
    median: f64,
    q3: f64,
    max: f64,
    outliers: Vec<f64>,
    samples: Vec<f64>,
}

async fn run_measurement(
    swarm: &mut Swarm<Behaviour>,
    peer_id: PeerId,
    upload_bytes: u64,
    download_bytes: u64,
    iterations: u32,
    debug: bool,
) -> Result<Stats> {
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
            if let Some(event) = swarm.next().await {
                match event {
                    swarm::SwarmEvent::Behaviour(BehaviourEvent::RequestResponse(
                        request_response::Event::Message {
                            message:
                                request_response::Message::Response {
                                    request_id: id,
                                    response,
                                },
                            ..
                        },
                    )) if id == request_id => {
                        break Some(response);
                    }
                    swarm::SwarmEvent::Behaviour(BehaviourEvent::RequestResponse(
                        request_response::Event::OutboundFailure {
                            request_id: id,
                            error,
                            ..
                        },
                    )) if id == request_id => {
                        eprintln!("  Iteration {}/{} failed: {:?}", i + 1, iterations, error);
                        break None;
                    }
                    _ => {}
                }
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
            if debug {
                eprintln!(
                    "DEBUG: Latency - elapsed={:.6}s, converted={:.3}ms",
                    elapsed, converted
                );
            }
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

    // Calculate percentiles
    let q1 = percentile(&values, 25.0);
    let median = percentile(&values, 50.0);
    let q3 = percentile(&values, 75.0);

    // Calculate IQR and identify outliers
    let iqr = q3 - q1;
    let lower_fence = q1 - 1.5 * iqr;
    let upper_fence = q3 + 1.5 * iqr;

    // Separate outliers from non-outliers
    let (outliers, non_outliers): (Vec<f64>, Vec<f64>) = values
        .iter()
        .partition(|&&v| v < lower_fence || v > upper_fence);

    // Calculate min/max from non-outliers (if any exist)
    let (min, max) = if !non_outliers.is_empty() {
        (non_outliers[0], non_outliers[non_outliers.len() - 1])
    } else {
        // Fallback if all values are outliers
        (values[0], values[n - 1])
    };

    Ok(Stats {
        min,
        q1,
        median,
        q3,
        max,
        outliers,
        samples: values,
    })
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

async fn build_swarm<B: swarm::NetworkBehaviour>(
    listen_ip: Option<String>,
    transport: Transport,
    secure_channel: Option<SecureChannel>,
    muxer: Option<Muxer>,
    behaviour_constructor: impl FnOnce(&Keypair) -> B,
) -> Result<(Swarm<B>, Option<Multiaddr>)> {
    let (swarm, addr) = match (transport, secure_channel, muxer) {
        (Transport::QuicV1, None, None) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_quic()
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/udp/0/quic-v1").parse().ok()),
        ),
        (Transport::Tcp, Some(SecureChannel::Tls), Some(Muxer::Mplex)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_tcp(
                    tcp::Config::default(),
                    tls::Config::new,
                    mplex::Config::default,
                )?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0").parse().ok()),
        ),
        (Transport::Tcp, Some(SecureChannel::Tls), Some(Muxer::Yamux)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_tcp(
                    tcp::Config::default(),
                    tls::Config::new,
                    yamux::Config::default,
                )?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0").parse().ok()),
        ),
        (Transport::Tcp, Some(SecureChannel::Noise), Some(Muxer::Mplex)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_tcp(
                    tcp::Config::default(),
                    noise::Config::new,
                    mplex::Config::default,
                )?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0").parse().ok()),
        ),
        (Transport::Tcp, Some(SecureChannel::Noise), Some(Muxer::Yamux)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_tcp(
                    tcp::Config::default(),
                    noise::Config::new,
                    yamux::Config::default,
                )?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0").parse().ok()),
        ),
        (Transport::Ws, Some(SecureChannel::Tls), Some(Muxer::Mplex)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_websocket(tls::Config::new, mplex::Config::default)
                .await?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0/ws").parse().ok()),
        ),
        (Transport::Ws, Some(SecureChannel::Tls), Some(Muxer::Yamux)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_websocket(tls::Config::new, yamux::Config::default)
                .await?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0/ws").parse().ok()),
        ),
        (Transport::Ws, Some(SecureChannel::Noise), Some(Muxer::Mplex)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_websocket(noise::Config::new, mplex::Config::default)
                .await?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0/ws").parse().ok()),
        ),
        (Transport::Ws, Some(SecureChannel::Noise), Some(Muxer::Yamux)) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_websocket(noise::Config::new, yamux::Config::default)
                .await?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/tcp/0/ws").parse().ok()),
        ),
        (Transport::WebrtcDirect, None, None) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_other_transport(|key| {
                    Ok(webrtc::tokio::Transport::new(
                        key.clone(),
                        webrtc::tokio::Certificate::generate(&mut rand::thread_rng())?,
                    ))
                })?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/udp/0/webrtc-direct").parse().ok()),
        ),
        (t, s, m) => bail!("Unsupported communication combination: {t:?} {s:?} {m:?}"),
    };
    Ok((swarm, addr))
}

/// Perf protocol behaviour
#[derive(swarm::NetworkBehaviour)]
struct Behaviour {
    request_response: request_response::Behaviour<PerfCodec>,
}

// Build the perf Behaviour
fn build_behaviour(_keypair: &Keypair) -> Behaviour {
    Behaviour {
        request_response: request_response::Behaviour::new(
            std::iter::once((PERF_PROTOCOL, ProtocolSupport::Full)),
            request_response::Config::default(),
        ),
    }
}

/// Supported transports
#[derive(Clone, Debug, Display, Eq, PartialEq, EnumString)]
#[strum(serialize_all = "kebab-case")]
enum Transport {
    Tcp,
    QuicV1,
    WebrtcDirect,
    Ws,
    Webtransport,
}

/// Supported secure channels
#[derive(Clone, Debug, Display, Eq, PartialEq, EnumString)]
#[strum(serialize_all = "kebab-case")]
enum SecureChannel {
    Noise,
    Tls,
}

/// Supported stream multiplexers
#[derive(Clone, Debug, Display, Eq, PartialEq, EnumString)]
#[strum(serialize_all = "kebab-case")]
enum Muxer {
    Mplex,
    Yamux,
}

#[cfg(test)]
mod test {
    use super::*;

    fn test_display_and_fromstr<V>(examples: &[(V, &str)])
    where
        V:  std::fmt::Display + 
            std::str::FromStr + 
            std::cmp::PartialEq +
            std::cmp::Eq +
            std::fmt::Debug,
        <V as std::str::FromStr>::Err: std::fmt::Debug
    {
        for (variant, expected) in examples {
            // Serialize using Display trait
            let serialized = format!("{variant}");
            assert_eq!(&serialized, *expected);

            // Deserialize using FromStr trait
            // The trait bounds on str::parse require V: FromStr
            let deserialized: V = expected.parse().unwrap();
            assert_eq!(*variant, deserialized);

            // Round trip using to_string() (implemented as part of Display)
            // and FromStr
            let s = variant.to_string();
            assert_eq!(s, *expected);
            let p: V = s.parse().unwrap();
            assert_eq!(*variant, p);
        }
    }

    #[test]
    fn transport() {
        use Transport::*;
        let examples = [
            (Tcp, "tcp"),
            (QuicV1, "quic-v1"),
            (WebrtcDirect, "webrtc-direct"),
            (Ws, "ws"),
            (Webtransport, "webtransport"),
        ];

        test_display_and_fromstr(&examples);
    }

    #[test]
    fn secure_channel() {
        use SecureChannel::*;
        let examples = [
            (Noise, "noise"),
            (Tls, "tls"),
        ];

        test_display_and_fromstr(&examples);
    }

    #[test]
    fn muxer() {
        use Muxer::*;
        let examples = [
            (Mplex, "mplex"),
            (Yamux, "yamux"),
        ];

        test_display_and_fromstr(&examples);
    }
}
