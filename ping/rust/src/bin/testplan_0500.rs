use anyhow::Result;
use async_trait::async_trait;
use futures::StreamExt;
use libp2pv0500::swarm::{keep_alive, NetworkBehaviour, SwarmEvent};
use libp2pv0500::{tokio_development_transport,webrtc};
use libp2pv0500::*;
use rand::thread_rng;
use std::collections::HashSet;
use std::env;
use std::time::Duration;
use testplan::*;
use crate::core::transport::Boxed;

#[async_std::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());
    let transport_env = env::var("TRANSPORT").unwrap_or_else(|_|"tcp".to_string());
    match transport_env.trim()  {
        "tcp" => {
            let transport = tokio_development_transport(local_key)?;
            let swarm = OrphanRuleWorkaround(Swarm::new(
                transport,
                Behaviour {
                    keep_alive: keep_alive::Behaviour,
                    ping: ping::Behaviour::new(ping::Config::new().with_interval(Duration::from_secs(1))),
                },
                local_peer_id,
            ));
            match transport_env.trim() {
                "tcp" => run_ping(swarm).await?,
                "webrtc" => run_ping_with_ma_pattern(swarm, "/ip4/ip4_address/udp/listening_port/webrtc".to_string()).await?,
                unhandled => unimplemented!("Transport unhandled in test: {}", unhandled),
            }
        },
        "webrtc" => {
            let transport = webrtc::tokio::Transport::new(
                local_key,
                webrtc::tokio::Certificate::generate(&mut thread_rng())?,
            ).boxed();
            let swarm = OrphanRuleWorkaround(Swarm::new(
                transport,
                Behaviour {
                    keep_alive: keep_alive::Behaviour,
                    ping: ping::Behaviour::new(ping::Config::new().with_interval(Duration::from_secs(1))),
                },
                local_peer_id,
            ));
            match transport_env.trim() {
                "tcp" => run_ping(swarm).await?,
                "webrtc" => run_ping_with_ma_pattern(swarm, "/ip4/ip4_address/udp/listening_port/webrtc".to_string()).await?,
                unhandled => unimplemented!("Transport unhandled in test: {}", unhandled),
            }
        },
        unhandled => unimplemented!("Transport unhandled in test: {}", unhandled),
    };

    Ok(())
}


#[derive(NetworkBehaviour)]
#[behaviour(prelude = "libp2pv0500::swarm::derive_prelude")]
struct Behaviour {
    keep_alive: keep_alive::Behaviour,
    ping: ping::Behaviour,
}

struct OrphanRuleWorkaround(Swarm<Behaviour>);

#[async_trait]
impl PingSwarm for OrphanRuleWorkaround {
    async fn listen_on(&mut self, address: &str) -> Result<()> {
        let id = self.0.listen_on(address.parse()?)?;

        loop {
            if let Some(SwarmEvent::NewListenAddr { listener_id, .. }) = self.0.next().await {
                if listener_id == id {
                    break;
                }
            }
        }

        Ok(())
    }

    fn dial(&mut self, address: &str) -> Result<()> {
        self.0.dial(address.parse::<Multiaddr>()?)?;

        Ok(())
    }

    async fn await_connections(&mut self, number: usize) {
        let mut connected = HashSet::with_capacity(number);

        while connected.len() < number {
            if let Some(SwarmEvent::ConnectionEstablished { peer_id, .. }) = self.0.next().await {
                connected.insert(peer_id);
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
