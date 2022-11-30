use anyhow::Result;
use async_trait::async_trait;
use futures::StreamExt;
use libp2pv0461::swarm::SwarmEvent;
use libp2pv0461::*;
use std::collections::HashSet;
use std::time::Duration;
use testplan::{run_ping, PingSwarm};

#[async_std::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());

    let swarm = OrphanRuleWorkaround(Swarm::new(
        development_transport(local_key).await?,
        ping::Behaviour::new(
            ping::Config::new()
                .with_interval(Duration::from_secs(1))
                .with_keep_alive(true),
        ),
        local_peer_id,
    ));

    run_ping(swarm).await?;

    Ok(())
}

struct OrphanRuleWorkaround(Swarm<ping::Behaviour>);

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
            if let Some(SwarmEvent::Behaviour(ping::Event {
                peer,
                result: Ok(ping::Success::Ping { .. }),
            })) = self.0.next().await
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
