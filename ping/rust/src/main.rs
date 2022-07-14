use std::collections::HashSet;
use std::str::FromStr;
use std::time::Duration;

use env_logger::Env;
use log::info;

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

    let num_other_instances = client.run_parameters().test_instance_count as usize - 1;

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
        .map(|a| Multiaddr::from_str(&a.unwrap()).unwrap())
        // Note: we sidestep simultaneous connect issues by ONLY connecting to peers
        // who published their addresses before us (this is enough to dedup and avoid
        // two peers dialling each other at the same time).
        //
        // We can do this because sync service pubsub is ordered.
        .take_while(|a| ready(a != &local_addr));

    client.publish("peers", local_addr.to_string()).await?;

    while let Some(addr) = address_stream.next().await {
        swarm.dial(addr).unwrap();
    }

    // Otherwise the testground background task gets blocked sending
    // subscription upgrades to the backpressured channel.
    drop(address_stream);

    info!("Wait to connect to each peer.");
    let mut connected = HashSet::new();
    while connected.len() < num_other_instances {
        let event = swarm.next().await.unwrap();
        info!("Event: {:?}", event);
        if let SwarmEvent::ConnectionEstablished { peer_id, .. } = event {
            connected.insert(peer_id);
        }
    }

    info!(
        "Signal and wait for \"connected\" from {:?}.",
        client.run_parameters().test_instance_count
    );
    let client_clone = client.clone();
    let mut connected_fut = client_clone
        .signal_and_wait("connected", client.run_parameters().test_instance_count)
        .boxed_local();
    loop {
        match futures::future::select(&mut connected_fut, swarm.next()).await {
            futures::future::Either::Left((Ok(_), _)) => break,
            futures::future::Either::Left((Err(e), _)) => {
                panic!("Failed to wait for \"conected\" barrier {:?}.", e)
            }
            futures::future::Either::Right((event, _)) => {
                info!("Event: {:?}", event);
            }
        }
    }

    info!("Wait to receive ping from each peer.");
    let mut pinged = HashSet::new();
    while pinged.len() < num_other_instances {
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

    info!("Wait for all peers to signal being done with \"initial\" round.");
    swarm
        .take_until(
            client
                .signal_and_wait("initial", client.run_parameters().test_instance_count)
                .boxed_local(),
        )
        .map(|event| info!("Event: {:?}", event))
        .collect::<Vec<()>>()
        .await;

    client.record_success().await?;

    Ok(())
}
