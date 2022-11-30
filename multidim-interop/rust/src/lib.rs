use anyhow::Result;
use env_logger::Env;
use futures::future::ready;
use futures::{FutureExt, StreamExt};
use log::info;
use rand::Rng;
use std::borrow::Cow;
use std::time::Duration;
use testground::client::Client;
use testground::network_conf::{
    FilterAction, LinkShape, NetworkConfiguration, RoutingPolicyType, DEFAULT_DATA_NETWORK,
};

const LISTENING_PORT: u16 = 1234;

#[async_trait::async_trait]
pub trait PingSwarm: Sized {
    async fn listen_on(&mut self, address: &str) -> Result<()>;

    fn dial(&mut self, address: &str) -> Result<()>;

    async fn await_connections(&mut self, number: usize);

    async fn await_pings(&mut self, number: usize);

    async fn loop_on_next(&mut self);

    fn local_peer_id(&self) -> String;
}

pub enum TransportKind {
    Tcp,
    WebSocket,
    Quic,
}

pub async fn run_ping<S>(client: Client, mut swarm: S, transport_kind: TransportKind) -> Result<()>
where
    S: PingSwarm,
{
    info!("Running ping test: {}", swarm.local_peer_id());

    env_logger::Builder::from_env(Env::default().default_filter_or("info")).init();

    let local_addr = match if_addrs::get_if_addrs()
        .unwrap()
        .into_iter()
        .find(|iface| iface.name == "eth1")
        .unwrap()
        .addr
        .ip()
    {
        std::net::IpAddr::V4(addr) => match transport_kind {
            TransportKind::Tcp => {
                format!("/ip4/{addr}/tcp/{LISTENING_PORT}")
            }
            TransportKind::WebSocket => {
                format!("/ip4/{addr}/tcp/{LISTENING_PORT}/ws")
            }
            TransportKind::Quic => {
                format!("/ip4/{addr}/udp/{LISTENING_PORT}/quic-v1")
            }
        },
        std::net::IpAddr::V6(_) => unimplemented!(),
    };

    info!(
        "Test instance, listening for incoming connections on: {:?}.",
        local_addr
    );

    swarm.listen_on(&local_addr).await?;

    let test_instance_count = client.run_parameters().test_instance_count as usize;
    let mut address_stream = client
        .subscribe("peers", test_instance_count)
        .await
        .take(test_instance_count)
        .map(|a| {
            let value = a.unwrap();
            value["Addrs"][0].as_str().unwrap().to_string()
        })
        // Note: we sidestep simultaneous connect issues by ONLY connecting to peers
        // who published their addresses before us (this is enough to dedup and avoid
        // two peers dialling each other at the same time).
        //
        // We can do this because sync service pubsub is ordered.
        .take_while(|a| ready(a != &local_addr));

    let payload = serde_json::json!({
        "ID": swarm.local_peer_id(),
        "Addrs": [
            local_addr
        ],
    });

    client.publish("peers", Cow::Owned(payload)).await?;

    while let Some(addr) = address_stream.next().await {
        swarm.dial(&addr).unwrap();
    }

    // Otherwise the testground background task gets blocked sending
    // subscription upgrades to the backpressured channel.
    drop(address_stream);

    info!("Wait to connect to each peer.");

    swarm
        .await_connections(client.run_parameters().test_instance_count as usize - 1)
        .await;

    signal_wait_and_drive_swarm(&client, &mut swarm, "connected".to_string()).await?;

    ping(&client, &mut swarm, "initial".to_string()).await?;

    let iterations: usize = 3;
    let max_latency_ms: u64 = 100;

    for i in 1..iterations + 1 {
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

async fn ping<S>(client: &testground::client::Client, swarm: &mut S, tag: String) -> Result<()>
where
    S: PingSwarm,
{
    info!("Wait to receive ping from each peer.");

    swarm
        .await_pings(client.run_parameters().test_instance_count as usize - 1)
        .await;

    signal_wait_and_drive_swarm(client, swarm, tag).await
}

async fn signal_wait_and_drive_swarm<S>(
    client: &testground::client::Client,
    swarm: &mut S,
    tag: String,
) -> Result<()>
where
    S: PingSwarm,
{
    info!(
        "Signal and wait for all peers to signal being done with \"{}\".",
        tag
    );

    // `loop_on_next` never finishes, so effectively, we run it until `signal_and_wait` finishes.
    futures::future::select(
        swarm.loop_on_next(),
        client
            .signal_and_wait(tag, client.run_parameters().test_instance_count)
            .boxed_local(),
    )
    .await;

    Ok(())
}
