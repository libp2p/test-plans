use anyhow::Result;
use async_trait::async_trait;
use futures::StreamExt;
use libp2pv0500::swarm::{keep_alive, NetworkBehaviour, SwarmEvent};
use libp2pv0500::{tokio_development_transport,webrtc};
use libp2pv0500::core::multiaddr::*;
use libp2pv0500::core::muxing::*;
use libp2pv0500::*;
use rand::thread_rng;
use std::{
    collections::HashSet,
    time::Duration,
};
use log::info;
use testplan::*;

#[async_std::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());
    let client = testground::client::Client::new_and_init().await.unwrap();
    let transport_name = client
        .run_parameters()
        .test_instance_params
        .get("transport")
        .expect("transport testparam should be available, possibly defaulted")
        .clone();
    let transport = match transport_name.as_str()  {
        "tcp" =>  tokio_development_transport(local_key)?,
        "webrtc" =>  webrtc::tokio::Transport::new(
                local_key,
                webrtc::tokio::Certificate::generate(&mut thread_rng())?)
            .map(|(peer_id, conn), _| (peer_id, StreamMuxerBox::new(conn)))
            .boxed(),
        unhandled => unimplemented!("Transport unhandled in test: '{}'", unhandled),
    };
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
#[behaviour(prelude = "libp2pv0500::swarm::derive_prelude")]
struct Behaviour {
    keep_alive: keep_alive::Behaviour,
    ping: ping::Behaviour,
}

struct OrphanRuleWorkaround(Swarm<Behaviour>);

#[async_trait]
impl PingSwarm for OrphanRuleWorkaround {
    async fn listen_on(&mut self, address: &str) -> Result<Option<String>> {
        let id = self.0.listen_on(address.parse()?)?;
        loop {
            if let Some(SwarmEvent::NewListenAddr { listener_id, address }) = self.0.next().await {
                if listener_id == id {
                    info!("NewListenAddr event: listener_id={:?}, address={:?}", &listener_id, &address);
                    return Ok(Some(address.to_string()));
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
                Some(SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. }) => {
                    info!("Connection established! {:?}={:?}", &peer_id, &endpoint);
                    connected.insert(peer_id);
                },
                Some(event) => info!("Received event {:?}",&event),
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
