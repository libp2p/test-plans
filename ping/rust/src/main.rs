use std::borrow::Cow;
use std::collections::HashSet;
use std::str::FromStr;
use std::time::Duration;

use env_logger::Env;
use log::info;
use rand::Rng;
use testground::network_conf::{
    FilterAction, LinkShape, NetworkConfiguration, RoutingPolicyType, DEFAULT_DATA_NETWORK,
};

pub mod libp2p {
    #[cfg(all(feature = "libp2pv0470",))]
    pub use libp2pv0470::*;

    #[cfg(all(feature = "libp2pv0460",))]
    pub use libp2pv0460::*;

    #[cfg(all(feature = "libp2pv0450",))]
    pub use libp2pv0450::*;

    #[cfg(all(feature = "libp2pv0440",))]
    pub use libp2pv0440::*;
}

use libp2p::futures::future::ready;
use libp2p::futures::{FutureExt, StreamExt};
use libp2p::swarm::{Swarm, SwarmEvent};
use libp2p::{development_transport, identity, multiaddr::Protocol, ping, Multiaddr, PeerId};

const LISTENING_PORT: u16 = 1234;

#[async_std::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(Env::default().default_filter_or("info")).init();

    let client = testground::client::Client::new_and_init().await?;

    let mut swarm = {
        let local_key = identity::Keypair::generate_ed25519();
        let local_peer_id = PeerId::from(local_key.public());
        info!("Local peer id: {:?}", local_peer_id);

        Swarm::new(
            development_transport(local_key).await?,
            ping::Behaviour::new(
                ping::Config::new()
                    .with_interval(Duration::from_secs(10))
                    .with_keep_alive(true),
            ),
            local_peer_id,
        )
    };

    let local_addr: Multiaddr = {
        let ip_addr = match if_addrs::get_if_addrs()
            .unwrap()
            .into_iter()
            .find(|iface| iface.name == "eth1")
            .unwrap()
            .addr
            .ip()
        {
            std::net::IpAddr::V4(addr) => addr,
            std::net::IpAddr::V6(_) => unimplemented!(),
        };

        Multiaddr::empty()
            .with(Protocol::Ip4(ip_addr))
            .with(Protocol::Tcp(LISTENING_PORT))
    };

    info!(
        "Test instance, listening for incoming connections on: {:?}.",
        local_addr
    );
    swarm.listen_on(local_addr.clone())?;
    match swarm.next().await.unwrap() {
        SwarmEvent::NewListenAddr { address, .. } if address == local_addr => {}
        e => panic!("Unexpected event {:?}", e),
    }

    let mut address_stream = client
        .subscribe("peers")
        .await
        .take(client.run_parameters().test_instance_count as usize)
        .map(|a| {
            let value = a.unwrap();
            let addr = value["Addrs"][0].as_str().unwrap();
            Multiaddr::from_str(addr).unwrap()
        })
        // Note: we sidestep simultaneous connect issues by ONLY connecting to peers
        // who published their addresses before us (this is enough to dedup and avoid
        // two peers dialling each other at the same time).
        //
        // We can do this because sync service pubsub is ordered.
        .take_while(|a| ready(a != &local_addr));

    let payload = serde_json::json!({
        "ID": swarm.local_peer_id().to_string(),
        "Addrs": [
            local_addr.to_string(),
        ],
    });

    client.publish("peers", Cow::Owned(payload)).await?;

    while let Some(addr) = address_stream.next().await {
        swarm.dial(addr).unwrap();
    }

    // Otherwise the testground background task gets blocked sending
    // subscription upgrades to the backpressured channel.
    drop(address_stream);

    info!("Wait to connect to each peer.");
    let mut connected = HashSet::new();
    while connected.len() < client.run_parameters().test_instance_count as usize - 1 {
        let event = swarm.next().await.unwrap();
        info!("Event: {:?}", event);
        if let SwarmEvent::ConnectionEstablished { peer_id, .. } = event {
            connected.insert(peer_id);
        }
    }

    signal_wait_and_drive_swarm(&client, &mut swarm, "connected".to_string()).await?;

    ping(&client, &mut swarm, "initial".to_string()).await?;

    let iterations: usize = client
        .run_parameters()
        .test_instance_params
        .get("iterations")
        .unwrap()
        .parse()
        .unwrap();
    let max_latency_ms: u64 = client
        .run_parameters()
        .test_instance_params
        .get("max_latency_ms")
        .unwrap()
        .parse()
        .unwrap();

    for i in 0..iterations {
        client.record_message(format!("⚡️  ITERATION ROUND {}", i));

        let latency = Duration::from_millis(rand::thread_rng().gen_range(0..max_latency_ms))
            .as_nanos()
            .try_into()
            .unwrap();

        let network_conf = NetworkConfiguration {
            network: DEFAULT_DATA_NETWORK.to_owned(),
            ipv4: None,
            ipv6: None,
            enable: true,
            default: LinkShape {
                latency,
                jitter: 0,
                bandwidth: 0,
                filter: FilterAction::Accept,
                loss: 0.0,
                corrupt: 0.0,
                corrupt_corr: 0.0,
                reorder: 0.0,
                reorder_corr: 0.0,
                duplicate: 0.0,
                duplicate_corr: 0.0,
            },
            rules: None,
            callback_state: format!("network-configured-{}", i),
            callback_target: Some(client.run_parameters().test_instance_count),
            routing_policy: RoutingPolicyType::AllowAll,
        };

        client.configure_network(network_conf).await.unwrap();

        ping(&client, &mut swarm, format!("done-{}", i)).await?;
    }

    client.record_success().await?;

    Ok(())
}

async fn ping(
    client: &testground::client::Client,
    swarm: &mut Swarm<ping::Behaviour>,
    tag: String,
) -> Result<(), Box<dyn std::error::Error>> {
    info!("Wait to receive ping from each peer.");
    let mut pinged = HashSet::new();
    while pinged.len() < client.run_parameters().test_instance_count as usize - 1 {
        let event = swarm.next().await.unwrap();
        info!("Event: {:?}", event);
        if let SwarmEvent::Behaviour(ping::PingEvent {
            peer,
            result: Ok(ping::PingSuccess::Ping { .. }),
        }) = event
        {
            pinged.insert(peer);
        }
    }

    signal_wait_and_drive_swarm(client, swarm, tag).await
}

async fn signal_wait_and_drive_swarm(
    client: &testground::client::Client,
    swarm: &mut Swarm<ping::Behaviour>,
    tag: String,
) -> Result<(), Box<dyn std::error::Error>> {
    info!(
        "Signal and wait for all peers to signal being done with \"{}\".",
        tag
    );
    swarm
        .take_until(
            client
                .signal_and_wait(tag, client.run_parameters().test_instance_count)
                .boxed_local(),
        )
        .map(|event| info!("Event: {:?}", event))
        .collect::<Vec<()>>()
        .await;

    Ok(())
}
