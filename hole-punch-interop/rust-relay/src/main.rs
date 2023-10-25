use anyhow::{bail, Context, Result};
use libp2p::{
    core::{
        multiaddr::{Multiaddr, Protocol},
        muxing::StreamMuxerBox,
        transport::Transport,
        upgrade,
    },
    futures::future::Either,
    futures::StreamExt,
    identify, identity, noise, ping, quic, relay,
    swarm::{NetworkBehaviour, SwarmBuilder, SwarmEvent},
    tcp, yamux, PeerId, Swarm,
};
use redis::AsyncCommands;
use std::net::{IpAddr, Ipv4Addr};

/// The redis key we push the relay's TCP listen address to.
const RELAY_TCP_ADDRESS: &str = "RELAY_TCP_ADDRESS";
/// The redis key we push the relay's QUIC listen address to.
const RELAY_QUIC_ADDRESS: &str = "RELAY_QUIC_ADDRESS";

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::builder()
        .parse_filters(
            "debug,netlink_proto=warn,rustls=warn,multistream_select=warn,libp2p_swarm::connection=info,quinn=debug,libp2p_quic=trace",
        )
        .parse_default_env()
        .init();

    let mut swarm = make_swarm()?;

    let tcp_listener_id = swarm.listen_on(tcp_addr(Ipv4Addr::UNSPECIFIED.into()))?;
    let quic_listener_id = swarm.listen_on(quic_addr(Ipv4Addr::UNSPECIFIED.into()))?;

    loop {
        match swarm.next().await.expect("Infinite Stream.") {
            SwarmEvent::NewListenAddr {
                address,
                listener_id,
            } => {
                let Some(Protocol::Ip4(addr)) = address.iter().next() else {
                    bail!("Expected first protocol of listen address to be Ip4")
                };

                if addr.is_loopback() {
                    log::debug!("Ignoring loop-back address: {address}");

                    continue;
                }

                swarm.add_external_address(address.clone()); // We know that in our testing network setup, that we are listening on a "publicly-reachable" address.

                log::info!("Listening on {address}");

                let address = address
                    .with(Protocol::P2p(*swarm.local_peer_id()))
                    .to_string();

                // Push each address twice because we need to connect two clients.

                let mut redis = RedisClient::new("redis", 6379).await?;

                if listener_id == tcp_listener_id {
                    redis.push(RELAY_TCP_ADDRESS, &address).await?;
                    redis.push(RELAY_TCP_ADDRESS, &address).await?;
                }
                if listener_id == quic_listener_id {
                    redis.push(RELAY_QUIC_ADDRESS, &address).await?;
                    redis.push(RELAY_QUIC_ADDRESS, &address).await?;
                }
            }
            other => {
                log::trace!("{other:?}")
            }
        }
    }
}

fn tcp_addr(addr: IpAddr) -> Multiaddr {
    Multiaddr::empty().with(addr.into()).with(Protocol::Tcp(0))
}

fn quic_addr(addr: IpAddr) -> Multiaddr {
    Multiaddr::empty()
        .with(addr.into())
        .with(Protocol::Udp(0))
        .with(Protocol::QuicV1)
}

fn make_swarm() -> Result<Swarm<Behaviour>> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());
    log::info!("Local peer id: {local_peer_id}");

    let transport = tcp::tokio::Transport::new(tcp::Config::default().nodelay(true))
        .upgrade(upgrade::Version::V1Lazy)
        .authenticate(noise::Config::new(&local_key)?)
        .multiplex(yamux::Config::default())
        .or_transport(quic::tokio::Transport::new(quic::Config::new(&local_key)))
        .map(|either_output, _| match either_output {
            Either::Left((peer_id, muxer)) => (peer_id, StreamMuxerBox::new(muxer)),
            Either::Right((peer_id, muxer)) => (peer_id, StreamMuxerBox::new(muxer)),
        })
        .boxed();
    let behaviour = Behaviour {
        relay: relay::Behaviour::new(local_peer_id, relay::Config::default()),
        identify: identify::Behaviour::new(identify::Config::new(
            "/hole-punch-tests/1".to_owned(),
            local_key.public(),
        )),
        ping: ping::Behaviour::default(),
    };

    Ok(
        SwarmBuilder::with_tokio_executor(transport, behaviour, local_peer_id)
            .substream_upgrade_protocol_override(upgrade::Version::V1Lazy)
            .build(),
    )
}

struct RedisClient {
    inner: redis::aio::Connection,
}

impl RedisClient {
    async fn new(host: &str, port: u16) -> Result<Self> {
        let client = redis::Client::open(format!("redis://{host}:{port}/"))
            .context("Bad redis server URL")?;
        let connection = client
            .get_async_connection()
            .await
            .context("Failed to connect to redis server")?;

        Ok(Self { inner: connection })
    }

    async fn push(&mut self, key: &str, value: impl ToString) -> Result<()> {
        self.inner.rpush(key, value.to_string()).await?;

        Ok(())
    }
}

#[derive(NetworkBehaviour)]
struct Behaviour {
    relay: relay::Behaviour,
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}
