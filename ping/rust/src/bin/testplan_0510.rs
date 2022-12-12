use anyhow::Result;
use async_trait::async_trait;
use futures::StreamExt;
use libp2pv0510::{
    core::{
        either::EitherOutput,
        muxing::StreamMuxerBox,
        upgrade::{SelectUpgrade,Version},
    },
    identity,
    mplex,
    noise,
    ping,
    swarm::{
        keep_alive,
        NetworkBehaviour,
        SwarmEvent
    },
    tcp,
    webrtc,
    yamux,
    Multiaddr,
    PeerId,
    Swarm,
    Transport,
};
use log::{debug, info};
use rand::thread_rng;
use std::collections::HashSet;
use std::time::Duration;
use testplan::{run_ping, PingSwarm};

#[tokio::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());
    let client = testground::client::Client::new_and_init()
        .await
        .expect("Unable to init testground cient.");
    let transport = tcp::tokio::Transport::default()
                .upgrade(Version::V1)
                .authenticate(noise::NoiseAuthenticated::xx(&local_key).unwrap())
                .multiplex(SelectUpgrade::new(
                    yamux::YamuxConfig::default(),
                    mplex::MplexConfig::default(),
                ))
                .timeout(Duration::from_secs(20))
                .or_transport(webrtc::tokio::Transport::new(
                    local_key,
                    webrtc::tokio::Certificate::generate(&mut thread_rng())?,
                ))
                .map(|either, _| match either {
                    EitherOutput::First((p, conn)) => (p, StreamMuxerBox::new(conn)),
                    EitherOutput::Second((p, conn)) => (p, StreamMuxerBox::new(conn)),
                })
                .boxed();
    let swarm = OrphanRuleWorkaround(Swarm::with_tokio_executor(
        transport,
        Behaviour {
            keep_alive: keep_alive::Behaviour,
            ping: ping::Behaviour::new(ping::Config::new().with_interval(Duration::from_secs(1))),
        },
        local_peer_id,
    ));

    run_ping(swarm, client).await?;

    Ok(())
}

#[derive(NetworkBehaviour)]
#[behaviour(prelude = "libp2pv0510::swarm::derive_prelude")]
struct Behaviour {
    keep_alive: keep_alive::Behaviour,
    ping: ping::Behaviour,
}

struct OrphanRuleWorkaround(Swarm<Behaviour>);

#[async_trait]
impl PingSwarm for OrphanRuleWorkaround {
    async fn listen_on(&mut self, address: &str) -> Result<String> {
        let id = self.0.listen_on(address.parse()?)?;

        loop {
            if let Some(SwarmEvent::NewListenAddr {
                            listener_id,
                            address,
                        }) = self.0.next().await
            {
                if listener_id == id {
                    return Ok(address.to_string());
                }
            }
        }
    }

    fn dial(&mut self, address: &str) -> Result<()> {
        self.0.dial(address.parse::<Multiaddr>()?)?;

        Ok(())
    }

    async fn await_connections(&mut self, number: usize) {
        let mut connected = HashSet::with_capacity(number);

        while connected.len() < number {
            match self.0.next().await {
                Some(SwarmEvent::ConnectionEstablished {
                         peer_id, endpoint, ..
                     }) => {
                    info!(
                        "Connection established! {}={}",
                        &peer_id,
                        &endpoint.get_remote_address()
                    );
                    connected.insert(peer_id);
                }
                Some(event) => debug!("Received event {:?}", &event), //This is useful, because it sometimes logs error messages
                None => (),
            }
        }
    }

    async fn await_pings(&mut self, number: usize) {
        let mut received_pings = HashSet::with_capacity(number);

        while received_pings.len() < number {
            if let Some(SwarmEvent::Behaviour(BehaviourEvent::Ping(ping::Event {
                peer,
                result: Ok(ping::Success::Ping { .. }),
            }))) = self.0.next().await
            {
                received_pings.insert(peer);
            }
        }
    }

    async fn loop_on_next(&mut self) {
        loop {
            self.0.next().await;
        }
    }

    fn local_peer_id(&self) -> String {
        self.0.local_peer_id().to_string()
    }
}
