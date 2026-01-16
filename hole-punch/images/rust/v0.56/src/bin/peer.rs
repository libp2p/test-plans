// Relay server for hole-punch tests

use anyhow::{bail, Context, Result};
use libp2p::{
    dcutr,
    futures::StreamExt,
    identify, 
    identity::Keypair,
    Multiaddr,
    multiaddr::Protocol,
    noise,
    PeerId,
    ping,
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

    // optional, defaults "0.0.0.0"
    let listener_ip = env::var("LISTENER_IP").unwrap_or("0.0.0.0".to_string());

    eprintln!("Starting hole-punch listener...");
    eprintln!("LISTENER_IP: {listener_ip}");

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
        None => bail!("failed to build listener multiaddr"),
    };

    eprintln!("Peer ID: {peer_id}");
    eprintln!("Will listen on: {listener_multiaddr}");

    // Step 1: listen and get our own local multiaddr

    // Start listening
    let id = swarm
        .listen_on(listener_multiaddr.clone())
        .expect("Failed to listen");

    // Wait for our listen to be ready
    loop {
        if let Some(swarm::SwarmEvent::NewListenAddr {
            listener_id,
            address,
        }) = swarm.next().await
        {
            eprintln!("Listener_id: {listener_id}, address: {address}");
            if address.to_string().contains("127.0.0.1") {
                eprintln!("Skipping localhost address");
                continue;
            }
            if listener_id == id {
                let local_multiaddr = format!("{address}/p2p/{peer_id}");
                eprintln!("Listening on local: {local_multiaddr}");
                break;
            }
        }
    }

    eprintln!("Listener ready, waiting for connections...");

    // Step 2: Wait for the relay to publish its multiaddr

    // Connect to Redis
    let client = redis::Client::open(redis_addr.clone()).expect("Failed to create Redis client");
    let mut con = client
        .get_multiplexed_async_connection()
        .await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {redis_addr}");

    // Wait for relay multiaddr (with retries)
    let relay_addr = wait_for_multiaddr(&mut con, &format!("{test_key}_relay_multiaddr")).await?;

    // Step 3: Dial the relay's multiaddr and get our observed multiaddr

    // dial the relay
    eprintln!("Dialing relay at: {relay_addr}");
    swarm.dial(relay_addr.clone()).expect("failed to dial relay");

    let mut sent_observed_addr = false;
    let mut my_observed_addr: Option<Multiaddr> = None;

    let external_addr = loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id,
                    connection_id,
                    ..
                } => {
                    eprintln!(
                        "Connection to relay: {peer_id} (connection: {connection_id:?})"
                    );
                }
                swarm::SwarmEvent::OutgoingConnectionError { error, .. } => {
                    bail!("Failed to connect: {error:?}");
                }
                swarm::SwarmEvent::NewExternalAddrCandidate { address } => {
                    eprintln!("A new external address for us is: {address}");
                    my_observed_addr = Some(address);
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(identify::Event::Sent {
                    ..
                })) => {
                    eprintln!("Identify sent to relay");
                    sent_observed_addr = true;
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(identify::Event::Received {
                    info: identify::Info { observed_addr, .. },
                    ..
                })) => {
                    eprintln!("Identify received to relay. observed addr: {observed_addr}");
                    my_observed_addr = Some(observed_addr);
                }
                other => {
                    if debug {
                        eprintln!("{other:?}");
                    }
                }
            }
        }

        if sent_observed_addr && my_observed_addr.is_some() {
            break my_observed_addr.unwrap()
        }
    };

    eprintln!("Listener external multiaddr: {external_addr}");

    let relayed_listener_addr = relay_addr.clone()
        .with(Protocol::P2pCircuit)
        .with(Protocol::P2p(peer_id));

    eprintln!("Listening on relayed circuit: {relayed_listener_addr}");

    // Step 4: Listen on the relayed circuit
    swarm
        .listen_on(relayed_listener_addr.clone())
        .expect("failed to listen on p2p circuit");
    
    // Publish to Redis with TEST_KEY namespacing
    let listener_peer_id_key = format!("{test_key}_listener_peer_id");
    let _: () = con
        .set(&listener_peer_id_key, relayed_listener_addr.to_string())
        .await
        .expect(&format!(
            "Failed to publish peer id to Redis: (key: {listener_peer_id_key})"
        ));
    eprintln!("Published peer id to Redis (key: {listener_peer_id_key})");

    let mut hole_punch_connection_id = None;

    // Wait for our listen to be ready and publish multiaddr
    loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::NewListenAddr {
                    listener_id,
                    address,
                } => {
                    eprintln!("Listener_id: {listener_id}, address: {address}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(
                    relay::client::Event::ReservationReqAccepted { .. },
                )) => {
                    eprintln!("Relay accepted our reservation request");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(
                    relay::client::Event::InboundCircuitEstablished { src_peer_id, .. },
                )) => {
                    eprintln!("Outbound relay circuit established ({src_peer_id})");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(event)) => {
                    eprintln!("{event:?}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Dcutr(
                    dcutr::Event { remote_peer_id, result }
                )) => {
                    match result {
                        Ok(connection_id) => {
                            eprintln!("dcutr to {remote_peer_id} succeeded!!");
                            hole_punch_connection_id = Some(connection_id);
                        }
                        Err(e) => {
                            bail!("dcutr failed {e:?}");
                        }
                    }
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(event)) => {
                    eprintln!("{event:?}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Ping(
                    ping::Event { connection, result, .. }
                )) => {
                    match result {
                        Ok(rtt) if Some(connection) == hole_punch_connection_id => {
                            eprintln!(
                                "Recevied ping over hole-punch connection: {}",
                                rtt.as_micros() as f32 / 1000.
                            );
                            return Ok(());
                        }
                        Err(e) if Some(connection) == hole_punch_connection_id => {
                            bail!("Ping failed over hole-punch connection {e:?}");
                        }
                        _ => {}
                    }
                }
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id, endpoint, ..
                } => {
                    eprintln!("New connection from {peer_id} details: {endpoint:?}");
                }
                other => {
                    if debug {
                        eprintln!("{other:?}");
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

    // optional, defaults "0.0.0.0"
    let dialer_ip = env::var("DIALER_IP").unwrap_or("0.0.0.0".to_string());

    eprintln!("Starting hole-punch dialer...");
    eprintln!("DIALER_IP: {dialer_ip}");

    // Build libp2p swarm
    let (mut swarm, multiaddr) = build_swarm(
        Some(dialer_ip),
        transport,
        secure_channel,
        muxer,
        build_behaviour
    ).await?;

    // get peer id and multiaddr to listen on
    let peer_id = *swarm.local_peer_id();
    let dialer_multiaddr = match multiaddr {
        Some(addr) => addr,
        None => bail!("failed to build dialer multiaddr"),
    };

    eprintln!("Peer ID: {peer_id}");
    eprintln!("Will listen on: {dialer_multiaddr}");

    // Step 1: listen and get our own local multiaddr

    // Start listening
    let id = swarm
        .listen_on(dialer_multiaddr.clone())
        .expect("Failed to listen");

    // Wait for our listen to be ready
    loop {
        if let Some(swarm::SwarmEvent::NewListenAddr {
            listener_id,
            address,
        }) = swarm.next().await
        {
            eprintln!("Listener_id: {listener_id}, address: {address}");
            if address.to_string().contains("127.0.0.1") {
                eprintln!("Skipping localhost address");
                continue;
            }
            if listener_id == id {
                let local_multiaddr = format!("{address}/p2p/{peer_id}");
                eprintln!("Listening on local: {local_multiaddr}");
                break;
            }
        }
    }

    eprintln!("Dialer ready, waiting for connections...");

    // Step 2: Wait for the relay to publish its multiaddr

    // Connect to Redis
    let client = redis::Client::open(redis_addr.clone()).expect("Failed to create Redis client");
    let mut con = client
        .get_multiplexed_async_connection()
        .await
        .expect("Failed to connect to Redis");

    eprintln!("Connected to Redis at {redis_addr}");

    // Wait for relay multiaddr (with retries)
    let relay_addr = wait_for_multiaddr(&mut con, &format!("{test_key}_relay_multiaddr")).await?;

    // Step 3: Dial the relay's multiaddr and get our observed multiaddr

    // dial the relay
    eprintln!("Dialing relay at: {relay_addr}");
    swarm.dial(relay_addr.clone())
        .expect("failed to dial relay");

    let mut sent_observed_addr = false;
    let mut my_observed_addr: Option<Multiaddr> = None;

    let external_addr = loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id,
                    connection_id,
                    ..
                } => {
                    eprintln!(
                        "Connection to relay: {peer_id} (connection: {connection_id:?})"
                    );
                }
                swarm::SwarmEvent::OutgoingConnectionError { error, .. } => {
                    bail!("Failed to connect: {error:?}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(identify::Event::Sent {
                    ..
                })) => {
                    sent_observed_addr = true;
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(identify::Event::Received {
                    info: identify::Info { observed_addr, .. },
                    ..
                })) => {
                    my_observed_addr = Some(observed_addr);
                }
                other => {
                    if debug {
                        eprintln!("{other:?}");
                    }
                }
            }
        }

        if sent_observed_addr && my_observed_addr.is_some() {
            break my_observed_addr.unwrap()
        }
    };

    eprintln!("Listener observed multiaddr: {external_addr}");

    // Wait for listener peer id (with retries)
    let listener_peer_id = wait_for_peer_id(&mut con, &format!("{test_key}_listener_peer_id")).await?;

    // Step 4: Listen on the relayed circuit
    swarm
        .dial(relay_addr
            .with(Protocol::P2pCircuit)
            .with(Protocol::P2p(listener_peer_id)))
        .expect("failed to dial on p2p circuit");

    let mut hole_punch_connection_id = None;

    // Wait for our listen to be ready and publish multiaddr
    loop {
        if let Some(event) = swarm.next().await {
            match event {
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(
                    relay::client::Event::ReservationReqAccepted { .. },
                )) => {
                    eprintln!("Relay accepted our reservation request");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(
                    relay::client::Event::OutboundCircuitEstablished { relay_peer_id, .. },
                )) => {
                    eprintln!("Outbound relay circuit established ({relay_peer_id})");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::RelayClient(event)) => {
                    eprintln!("{event:?}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Dcutr(
                    dcutr::Event { remote_peer_id, result }
                )) => {
                    match result {
                        Ok(connection_id) => {
                            eprintln!("dcutr to {remote_peer_id} succeeded!!");
                            hole_punch_connection_id = Some(connection_id);
                        }
                        Err(e) => {
                            bail!("dcutr failed {e:?}");
                        }
                    }
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Identify(event)) => {
                    eprintln!("{event:?}");
                }
                swarm::SwarmEvent::Behaviour(BehaviourEvent::Ping(
                    ping::Event { connection, result, .. }
                )) => {
                    match result {
                        Ok(rtt) if Some(connection) == hole_punch_connection_id => {
                            eprintln!(
                                "Recevied ping over hole-punch connection: {}",
                                rtt.as_micros() as f32 / 1000.
                            );
                            return Ok(());
                        }
                        Err(e) if Some(connection) == hole_punch_connection_id => {
                            bail!("Ping failed over hole-punch connection {e:?}");
                        }
                        _ => {}
                    }
                }
                swarm::SwarmEvent::ConnectionEstablished {
                    peer_id, endpoint, ..
                } => {
                    eprintln!("New connection from {peer_id} details: {endpoint:?}");
                }
                other => {
                    if debug {
                        eprintln!("{other:?}");
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
    behaviour_constructor: impl FnOnce(&Keypair, relay::client::Behaviour) -> B,
) -> Result<(Swarm<B>, Option<Multiaddr>)> {
    let (swarm, addr) = match (transport, secure_channel, muxer) {
        (Transport::QuicV1, None, None) => (
            libp2p::SwarmBuilder::with_new_identity()
                .with_tokio()
                .with_quic()
                .with_relay_client(noise::Config::new, yamux::Config::default)?
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
                .with_relay_client(tls::Config::new, mplex::Config::default)?
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
                .with_relay_client(tls::Config::new, yamux::Config::default)?
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
                .with_relay_client(noise::Config::new, mplex::Config::default)?
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
                .with_relay_client(noise::Config::new, yamux::Config::default)?
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
                .with_relay_client(tls::Config::new, mplex::Config::default)?
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
                .with_relay_client(tls::Config::new, yamux::Config::default)?
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
                .with_relay_client(noise::Config::new, mplex::Config::default)?
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
                .with_relay_client(noise::Config::new, yamux::Config::default)?
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
                .with_relay_client(noise::Config::new, yamux::Config::default)?
                .with_behaviour(behaviour_constructor)?
                .build(),
            listen_ip
                .and_then(|ip| format!("/ip4/{ip}/udp/0/webrtc-direct").parse().ok()),
        ),
        (t, s, m) => bail!("Unsupported communication combination: {t:?} {s:?} {m:?}"),
    };
    Ok((swarm, addr))
}

async fn wait_for_multiaddr(con: &mut redis::aio::MultiplexedConnection, key: &str) -> Result<Multiaddr> {
    eprintln!("Waiting for multiaddr from Redis (key: {key})");
    // retries 300 times, waiting a total of 150 seconds before panicking
    for _ in 0..300 {
        if let Ok(Some(addr)) = con.get::<_, Option<String>>(&key).await {
            eprintln!("Got multiaddr (key: {key})");
            return addr.parse().context("Invalid multiaddr from Redis");
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    panic!("Timeout waiting for multiaddr (key: {key})");
}

async fn wait_for_peer_id(con: &mut redis::aio::MultiplexedConnection, key: &str) -> Result<PeerId> {
    eprintln!("Waiting for peer id from Redis (key: {key})");
    // retries 30 times, waiting a total of 15 seconds before panicking
    for _ in 0..30 {
        if let Ok(Some(peer_id)) = con.get::<_, Option<String>>(&key).await {
            eprintln!("Got peer id (key: {key})");
            return peer_id.parse().context("Invalid peer id from Redis");
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    panic!("Timeout waiting for peer id (key: {key})");
}

/// Relay protocol behaviour
#[derive(swarm::NetworkBehaviour)]
struct Behaviour {
    relay_client: relay::client::Behaviour,
    ping: ping::Behaviour,
    identify: identify::Behaviour,
    dcutr: dcutr::Behaviour,
}

// Build the relay Behaviour
fn build_behaviour(keypair: &Keypair, relay_client_behaviour: relay::client::Behaviour) -> Behaviour {
    let peer_id = PeerId::from(keypair.public());
    Behaviour {
        relay_client: relay_client_behaviour,
        ping: ping::Behaviour::new(ping::Config::new()),
        identify: identify::Behaviour::new(identify::Config::new(
            "/hole-punch-tests/1".to_owned(),
            keypair.public(),
        )),
        dcutr: dcutr::Behaviour::new(peer_id),
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
