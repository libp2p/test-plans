//! AutoNAT v2 client for the test-plans interop suite. Runs as either the server
//! (an AutoNAT v2 service that dials addresses back) or the client (asks the
//! server to verify the reachability of its own address), orchestrated over redis.

use std::error::Error;
use std::time::Duration;

use futures::StreamExt;
use libp2p::multiaddr::Protocol;
use libp2p::swarm::{FromSwarm, NetworkBehaviour, NewExternalAddrCandidate, SwarmEvent};
use libp2p::{autonat, identify, noise, tcp, yamux, Multiaddr, SwarmBuilder};
use redis::aio::MultiplexedConnection;

/// The fixed address of the orchestrating redis server.
const REDIS_URL: &str = "redis://redis:6379";

/// The redis list the server pushes its dialable multiaddr to and the client
/// pops it from.
const SERVER_ADDR_KEY: &str = "AUTONAT_SERVER_ADDR";

/// Bounds the whole run. The compose runner tears the stack down at 60s, so the
/// client exits first with a status it can attribute.
const TEST_TIMEOUT: Duration = Duration::from_secs(55);

/// The protocol string reported over identify.
const IDENTIFY_PROTOCOL: &str = "/autonat-interop/1.0.0";

#[derive(NetworkBehaviour)]
struct ClientBehaviour {
    autonat: autonat::v2::client::Behaviour,
    identify: identify::Behaviour,
}

#[derive(NetworkBehaviour)]
struct ServerBehaviour {
    autonat: autonat::v2::server::Behaviour,
    identify: identify::Behaviour,
}

#[tokio::main]
async fn main() {
    if let Err(e) = run().await {
        eprintln!("autonat-client: FAILED: {e}");
        std::process::exit(1);
    }
}

async fn run() -> Result<(), Box<dyn Error>> {
    let transport = std::env::var("TRANSPORT").unwrap_or_default();
    match transport.as_str() {
        "tcp" | "quic" => {}
        other => return Err(format!("invalid TRANSPORT {other:?}").into()),
    }
    let mode = std::env::var("MODE").unwrap_or_default();

    let conn = connect_redis().await?;

    match mode.as_str() {
        "server" => run_server(&transport, conn).await,
        "client" => tokio::time::timeout(TEST_TIMEOUT, run_client(&transport, conn))
            .await
            .map_err(|_| "timed out waiting for a reachability verdict".into())
            .and_then(|r| r),
        other => Err(format!("invalid MODE {other:?}").into()),
    }
}

/// listen_addr returns the wildcard listen multiaddr for the transport.
fn listen_addr(transport: &str) -> &'static str {
    match transport {
        "quic" => "/ip4/0.0.0.0/udp/0/quic-v1",
        _ => "/ip4/0.0.0.0/tcp/0",
    }
}

/// runs the AutoNAT server. It publishes its dialable address and then serves
/// requests until the compose runner stops the container.
async fn run_server(transport: &str, mut conn: MultiplexedConnection) -> Result<(), Box<dyn Error>> {
    let mut swarm = SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_tcp(tcp::Config::default(), noise::Config::new, yamux::Config::default)?
        .with_quic()
        .with_behaviour(|key| ServerBehaviour {
            autonat: autonat::v2::server::Behaviour::default(),
            identify: identify::Behaviour::new(identify::Config::new(
                IDENTIFY_PROTOCOL.to_string(),
                key.public(),
            )),
        })?
        .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
        .build();

    swarm.listen_on(listen_addr(transport).parse()?)?;
    let local_peer_id = *swarm.local_peer_id();

    let mut published = false;
    loop {
        let event = swarm.select_next_some().await;
        if let SwarmEvent::NewListenAddr { address, .. } = event {
            if !published && is_usable(&address) {
                let full = address
                    .with_p2p(local_peer_id)
                    .map_err(|a| format!("encapsulating peer id into {a}"))?;
                rpush(&mut conn, SERVER_ADDR_KEY, &full.to_string()).await?;
                eprintln!("autonat-client: published server address: {full}");
                published = true;
            }
        }
    }
}

/// runs the AutoNAT client. It connects to the server, offers its own listen
/// address for verification and reports the verdict.
async fn run_client(transport: &str, mut conn: MultiplexedConnection) -> Result<(), Box<dyn Error>> {
    let mut swarm = SwarmBuilder::with_new_identity()
        .with_tokio()
        .with_tcp(tcp::Config::default(), noise::Config::new, yamux::Config::default)?
        .with_quic()
        .with_behaviour(|key| ClientBehaviour {
            autonat: autonat::v2::client::Behaviour::default(),
            identify: identify::Behaviour::new(identify::Config::new(
                IDENTIFY_PROTOCOL.to_string(),
                key.public(),
            )),
        })?
        .with_swarm_config(|c| c.with_idle_connection_timeout(Duration::from_secs(60)))
        .build();

    swarm.listen_on(listen_addr(transport).parse()?)?;

    let server_value = blpop(&mut conn, SERVER_ADDR_KEY, 50).await?;
    let server_addr: Multiaddr = server_value.parse()?;
    eprintln!("autonat-client: server address: {server_addr}");
    swarm.dial(server_addr)?;

    // The address the server is asked to verify. Set from the first usable
    // listen address and offered to the AutoNAT client as an external address
    // candidate, which is the only input the client tests.
    let mut candidate: Option<Multiaddr> = None;

    loop {
        match swarm.select_next_some().await {
            SwarmEvent::NewListenAddr { address, .. } => {
                if candidate.is_none() && is_usable(&address) {
                    swarm.behaviour_mut().autonat.on_swarm_event(
                        FromSwarm::NewExternalAddrCandidate(NewExternalAddrCandidate {
                            addr: &address,
                        }),
                    );
                    eprintln!("autonat-client: offering candidate: {address}");
                    candidate = Some(address);
                }
            }
            SwarmEvent::Behaviour(ClientBehaviourEvent::Autonat(
                autonat::v2::client::Event {
                    tested_addr,
                    result,
                    ..
                },
            )) => {
                if candidate.as_ref() != Some(&tested_addr) {
                    continue;
                }
                let reachable = result.is_ok();
                println!(
                    "{{\"reachable\":{},\"tested_addr\":{:?}}}",
                    reachable,
                    tested_addr.to_string()
                );
                if reachable {
                    return Ok(());
                }
                return Err(format!(
                    "address {tested_addr} reported not reachable: {result:?}"
                )
                .into());
            }
            _ => {}
        }
    }
}

/// is_usable reports whether the address is a concrete, dialable interface
/// address rather than loopback or the unspecified wildcard.
fn is_usable(addr: &Multiaddr) -> bool {
    for p in addr.iter() {
        match p {
            Protocol::Ip4(ip) => return !ip.is_loopback() && !ip.is_unspecified(),
            Protocol::Ip6(ip) => return !ip.is_loopback() && !ip.is_unspecified(),
            _ => {}
        }
    }
    false
}

/// connect_redis opens a multiplexed connection, retrying until redis is ready.
async fn connect_redis() -> Result<MultiplexedConnection, Box<dyn Error>> {
    let client = redis::Client::open(REDIS_URL)?;
    for _ in 0..300 {
        match client.get_multiplexed_async_connection().await {
            Ok(conn) => return Ok(conn),
            Err(_) => tokio::time::sleep(Duration::from_millis(200)).await,
        }
    }
    Err("timed out waiting for redis".into())
}

async fn rpush(conn: &mut MultiplexedConnection, key: &str, value: &str) -> Result<(), Box<dyn Error>> {
    let _: () = redis::cmd("RPUSH")
        .arg(key)
        .arg(value)
        .query_async(conn)
        .await?;
    Ok(())
}

/// blpop blocks on a redis list until an entry is available or timeout seconds
/// pass, returning the popped value.
async fn blpop(conn: &mut MultiplexedConnection, key: &str, timeout: u64) -> Result<String, Box<dyn Error>> {
    let parts: Vec<String> = redis::cmd("BLPOP")
        .arg(key)
        .arg(timeout)
        .query_async(conn)
        .await?;
    parts
        .into_iter()
        .nth(1)
        .ok_or_else(|| "redis BLPOP timed out".into())
}
