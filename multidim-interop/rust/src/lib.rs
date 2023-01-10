use anyhow::{Context, Result};
use env_logger::Env;
use libp2pv0500::PeerId;
use log::info;
use redis::{AsyncCommands, Client as Rclient};
use std::{env, time::Duration};

const REDIS_TIMEOUT: usize = 10;

#[async_trait::async_trait]
pub trait PingSwarm: Sized {
    async fn listen_on(&mut self, address: &str) -> Result<String>;

    fn dial(&mut self, address: &str) -> Result<()>;

    async fn await_connections(&mut self, number: usize);

    async fn await_pings(&mut self, number: usize) -> Vec<Duration>;

    async fn loop_on_next(&mut self);

    fn local_peer_id(&self) -> String;
}

pub enum TransportKind {
    Tcp,
    WebSocket,
    Quic,
}

pub async fn run_ping_redis<S>(
    client: Rclient,
    mut swarm: S,
    local_addr: &str,
    local_peer_id: PeerId,
) -> Result<()>
where
    S: PingSwarm,
{
    let mut conn = client.get_async_connection().await?;

    info!("Running ping test: {}", swarm.local_peer_id());
    env_logger::Builder::from_env(Env::default().default_filter_or("info")).init();

    let is_dialer = env::var("is_dialer")
        .unwrap_or("true".into())
        .parse::<bool>()?;

    if is_dialer {
        let result: Vec<String> = conn.blpop("listenerAddr", REDIS_TIMEOUT).await?;
        let other = result
            .get(1)
            .context("Failed to wait for listener to be ready")?;

        swarm.dial(other)?;
        info!("Test instance, dialing multiaddress on: {}.", other);

        swarm.await_connections(1).await;

        let results = swarm.await_pings(1).await;

        conn.rpush("dialerDone", "").await?;
        info!(
            "Ping successful: {:?}",
            results.first().expect("Should have a ping result")
        );
    } else {
        let local_addr = swarm.listen_on(local_addr).await?;
        let ma = format!("{local_addr}/p2p/{local_peer_id}");
        conn.rpush("listenerAddr", ma).await?;
        info!(
            "Test instance, listening for incoming connections on: {:?}.",
            local_addr
        );

        swarm.await_connections(1).await;

        let _done: Vec<String> = conn.blpop("dialerDone", REDIS_TIMEOUT).await?;
        info!("Ping successful");
    }

    Ok(())
}
