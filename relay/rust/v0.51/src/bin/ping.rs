use std::env;
use std::str::FromStr;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use either::Either;
use env_logger::{Env, Target};
use futures::StreamExt;
use libp2p::core::muxing::StreamMuxerBox;
use libp2p::core::transport::OrTransport;
use libp2p::core::upgrade::Version;
use libp2p::multiaddr::Protocol;
use libp2p::swarm::{keep_alive, AddressScore, NetworkBehaviour, SwarmEvent};
use libp2p::{identity, noise, ping, tcp, yamux, Multiaddr, PeerId, Swarm, Transport as _};
use redis::AsyncCommands;

#[tokio::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());

    let role_param: Role = from_env("role")?;
    let test_timeout = env::var("test_timeout_seconds")
        .unwrap_or_else(|_| "180".into())
        .parse::<u64>()?;

    let redis_addr = env::var("redis_addr")
        .map(|addr| format!("redis://{addr}"))
        .unwrap_or_else(|_| "redis://redis:6379".into());

    let client = redis::Client::open(redis_addr).context("Could not connect to redis")?;

    let (boxed_transport, local_addr) = (
        tcp::tokio::Transport::new(tcp::Config::new())
            .upgrade(Version::V1Lazy)
            .authenticate(
                noise::NoiseAuthenticated::xx(&local_key).context("failed to intialise noise")?,
            )
            .multiplex(yamux::YamuxConfig::default())
            .timeout(Duration::from_secs(5))
            .boxed(),
        format!("/ip4/0.0.0.0/tcp/0"),
    );

    let (boxed_transport, relay_behaviour) = match role_param {
        Role::Source | Role::Destination => {
            let (transport, behaviour) = libp2p::relay::client::new(local_peer_id);

            let transport = transport
                .upgrade(libp2p::core::upgrade::Version::V1Lazy)
                // TODO: Do we want to test other encryption mechanisms than noise?
                .authenticate(noise::NoiseAuthenticated::xx(&local_key).unwrap())
                // TODO: Do we want to test other multiplexing mechanisms than yamux?
                .multiplex(yamux::YamuxConfig::default())
                .timeout(Duration::from_secs(20));

            (
                OrTransport::new(transport, boxed_transport)
                    .map(|either_output, _| match either_output {
                        futures::future::Either::Left((peer_id, muxer)) => {
                            (peer_id, StreamMuxerBox::new(muxer))
                        }
                        futures::future::Either::Right((peer_id, muxer)) => {
                            (peer_id, StreamMuxerBox::new(muxer))
                        }
                    })
                    .boxed(),
                Either::Left(behaviour),
            )
        }
        Role::Relay => (
            boxed_transport,
            Either::Right(libp2p::relay::Behaviour::new(
                local_peer_id,
                Default::default(),
            )),
        ),
    };

    let mut swarm = Swarm::with_tokio_executor(
        boxed_transport,
        Behaviour {
            ping: ping::Behaviour::new(ping::Config::new().with_interval(Duration::from_secs(1))),
            keep_alive: keep_alive::Behaviour,
            relay: relay_behaviour,
        },
        local_peer_id,
    );

    let mut conn = client.get_async_connection().await?;

    log::info!("Running relay test: {}", swarm.local_peer_id());
    env_logger::Builder::from_env(Env::default().default_filter_or("info"))
        .target(Target::Stdout)
        .init();

    log::info!(
        "Test instance, listening for incoming connections on: {:?}.",
        local_addr
    );
    let id = swarm.listen_on(local_addr.parse()?)?;

    match role_param {
        Role::Source => {
            let result: Vec<String> = conn.blpop("listenerAddr", test_timeout as usize).await?;
            let other = result
                .get(1)
                .context("Failed to wait for listener to be ready")?;

            let ma = other.parse::<Multiaddr>()?;

            let (relay_peer_id, destination_peer_id) = {
                let mut i = ma.iter().filter_map(|p| match p {
                    Protocol::P2p(hash) => Some(PeerId::from_multihash(hash).unwrap()),
                    _ => None,
                });
                (i.next().unwrap(), i.next().unwrap())
            };

            swarm.dial(ma)?;
            log::info!("Test instance, dialing multiaddress on: {}.", other);

            loop {
                if let Some(SwarmEvent::Behaviour(BehaviourEvent::Ping(ping::Event {
                    peer,
                    result: Ok(ping::Success::Ping { rtt }),
                }))) = swarm.next().await
                {
                    if peer == destination_peer_id {
                        log::info!("Ping to destination successful: {rtt:?}");
                        break;
                    } else if peer == relay_peer_id {
                        log::info!("Ping to relay successful");
                    } else {
                        panic!()
                    }
                }
            }
        }
        Role::Relay => {
            loop {
                if let Some(SwarmEvent::NewListenAddr {
                    listener_id,
                    address,
                }) = swarm.next().await
                {
                    if address.to_string().contains("127.0.0.1") {
                        continue;
                    }
                    if listener_id == id {
                        swarm.add_external_address(address.clone(), AddressScore::Infinite);
                        let ma = format!("{address}/p2p/{local_peer_id}");
                        log::info!("Publishing address {}", ma);
                        conn.rpush("relayListenerAddr", ma).await?;
                        break;
                    }
                }
            }

            // Drive Swarm in the background while we await for `dialerDone` to be ready.
            tokio::spawn(async move {
                loop {
                    swarm.next().await;
                }
            });
            tokio::time::sleep(Duration::from_secs(test_timeout)).await;
            bail!("Test should have been killed by the test runner!");
        }
        Role::Destination => {
            let result: Vec<String> = conn
                .blpop("relayListenerAddr", test_timeout as usize)
                .await?;
            let other = result
                .get(1)
                .context("Failed to wait for listener to be ready")?;

            log::info!("Got address of relay {}", other);
            let id = swarm.listen_on(
                other
                    .parse::<Multiaddr>()?
                    .with(Protocol::P2pCircuit)
                    .with(Protocol::P2p(local_peer_id.into())),
            )?;

            loop {
                if let Some(SwarmEvent::NewListenAddr {
                    listener_id,
                    address,
                }) = swarm.next().await
                {
                    if address.to_string().contains("127.0.0.1") {
                        continue;
                    }
                    if listener_id == id {
                        let ma = format!("{address}");
                        conn.rpush("listenerAddr", ma).await?;
                        break;
                    }
                }
            }

            // Drive Swarm in the background while we await for `dialerDone` to be ready.
            tokio::spawn(async move {
                loop {
                    swarm.next().await;
                }
            });
            tokio::time::sleep(Duration::from_secs(test_timeout)).await;
            bail!("Test should have been killed by the test runner!");
        }
    }

    Ok(())
}

/// Supported relay roles by rust-libp2p.
#[derive(Clone, Debug)]
pub enum Role {
    Source,
    Relay,
    Destination,
}

impl FromStr for Role {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        Ok(match s {
            "source" => Self::Source,
            "relay" => Self::Relay,
            "destination" => Self::Destination,
            other => bail!("unknown transport {other}"),
        })
    }
}

#[derive(NetworkBehaviour)]
struct Behaviour {
    ping: ping::Behaviour,
    keep_alive: keep_alive::Behaviour,
    relay: Either<libp2p::relay::client::Behaviour, libp2p::relay::Behaviour>,
}

/// Helper function to get a ENV variable into an test parameter like `Transport`.
pub fn from_env<T>(env_var: &str) -> Result<T>
where
    T: FromStr<Err = anyhow::Error>,
{
    env::var(env_var)
        .with_context(|| format!("{env_var} environment variable is not set"))?
        .parse()
        .map_err(Into::into)
}
