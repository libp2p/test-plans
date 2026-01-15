// Relay server for hole-punch tests

use anyhow::{bail, Context, Result};
use libp2p::{
    futures::StreamExt,
    identify, 
    identity::Keypair,
    Multiaddr,
    noise,
    PeerId,
    relay,
    swarm,
    Swarm,
    tcp,
    tls,
    yamux
};
use libp2p_mplex as mplex;
use libp2p_webrtc as webrtc;
use redis::AsyncCommands;
use std::{env, str};
use strum::{Display, EnumString};

#[tokio::main]
async fn main() -> Result<()> {
    // Read configuration from environment variables

    // optional, defaults to false
    let debug = env::var("DEBUG").ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(false);

    // required, ex. "redis:6379"
    let redis_addr = env::var("REDIS_ADDR")
        .context("REDIS_ADDR environment variable is not set")
        .map(|addr| format!("redis://{addr}"))?;

    // required, ex. "a1b2c3d4"
    let test_key = env::var("TEST_KEY")
        .context("TEST_KEY environment variable is not set")?;

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
    eprintln!("REDIS_ADDR: {redis_addr}");
    eprintln!("TEST_KEY: {test_key}");
    eprintln!("TRANSPORT: {transport}");
    eprintln!("SECURE_CHANNEL: {:?}", secure_channel);
    eprintln!("MUXER: {:?}", muxer);

    // optional, defaults to "0.0.0.0"
    let relay_ip = env::var("RELAY_IP").unwrap_or("0.0.0.0".to_string());

    eprintln!("Starting relay...");
    eprintln!("RELAY_IP: {relay_ip}");

    // Connect to Redis
    let client = redis::Client::open(redis_addr.clone()).expect("Failed to create Redis client");
    let mut con = client
        .get_multiplexed_async_connection()
        .await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {redis_addr}");

    // Build libp2p swarm
    let (mut swarm, multiaddr) = build_swarm(
        Some(relay_ip),
        transport,
        secure_channel,
        muxer,
        build_behaviour
    ).await?;

    // get peer id and multiaddr to listen on
    let peer_id = *swarm.local_peer_id();
    let relay_multiaddr = match multiaddr {
        Some(addr) => addr,
        None => bail!("failed to build relay multiaddr")
    };

    eprintln!("Peer ID: {peer_id}");
    eprintln!("Will listen on: {relay_multiaddr}");

    // Start listening
    let id = swarm
        .listen_on(relay_multiaddr.clone())
        .expect("Failed on listen");

    // Wait for our listen to be ready and publish multiaddr
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
                let relay_addr_key = format!("{test_key}_relay_multiaddr");
                let _: () = con
                    .set(&relay_addr_key, full_multiaddr.clone())
                    .await
                    .expect(&format!(
                        "Failed to publish multiaddr to Redis: (key: {relay_addr_key})"
                    ));

                eprintln!("Published multiaddr to Redis (key: {relay_addr_key})");
                break;
            }
        }
    }

    eprintln!("Relay ready, waiting for connections...");

    loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id,
                    connection_id,
                    ..
                } => {
                    eprintln!(
                        "Connection established with: {peer_id} (connection: {connection_id:?})"
                    );
                }

                swarm::SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                    eprintln!("Connection closed with {peer_id}: {cause:?}");
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

/// Relay protocol behaviour
#[derive(swarm::NetworkBehaviour)]
struct Behaviour {
    relay: relay::Behaviour,
    identify: identify::Behaviour,
}

// Build the relay Behaviour
fn build_behaviour(keypair: &Keypair) -> Behaviour {
    let peer_id = PeerId::from(keypair.public());
    Behaviour {
        relay: relay::Behaviour::new(peer_id, relay::Config::default()),
        identify: identify::Behaviour::new(identify::Config::new(
            "/hole-punch-tests/1".to_owned(),
            keypair.public(),
        )),
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
