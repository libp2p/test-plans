use anyhow::Result;
use async_trait::async_trait;
use futures::{AsyncRead, AsyncWrite, StreamExt};
use libp2p::core::transport::Boxed;
use libp2p::core::upgrade::EitherUpgrade;
use libp2p::noise::NoiseOutput;
use libp2p::tls::TlsStream;
use libp2p::{core::muxing::StreamMuxerBox, swarm::derive_prelude::EitherOutput};
use libp2pv0500 as libp2p;
use libp2pv0500::swarm::SwarmEvent;
use libp2pv0500::websocket::WsConfig;
use libp2pv0500::*;
use std::collections::HashSet;
use std::time::Duration;
use testground::client::Client as TGClient;
use testplan::{run_ping, PingSwarm, TransportKind};

fn build_builder<T, C>(
    builder: core::transport::upgrade::Builder<T>,
    secure_channel_param: String,
    muxer_param: String,
    local_key: identity::Keypair,
) -> Boxed<(libp2p::PeerId, StreamMuxerBox)>
where
    T: Transport<Output = C> + Send + Unpin + 'static,
    <T as libp2p::Transport>::Error: Sync + Send,
    <T as libp2p::Transport>::Error: 'static,
    <T as libp2p::Transport>::ListenerUpgrade: Send,
    <T as libp2p::Transport>::Dial: Send,
    C: AsyncRead + AsyncWrite + Send + Unpin + 'static,
{
    let secure_upgrade = match secure_channel_param.as_str() {
        "noise" => EitherUpgrade::A(libp2p::noise::NoiseAuthenticated::xx(&local_key).unwrap()),
        "tls" => EitherUpgrade::B(libp2p::tls::Config::new(&local_key).unwrap()),
        _ => panic!("Unsupported secure channel"),
    };

    trait AsyncRW: 'static + AsyncRead + AsyncWrite + Unpin + Send {}
    impl<T> AsyncRW for T where T: 'static + AsyncRead + AsyncWrite + Unpin + Send {}

    let f = |x: EitherOutput<
        (libp2p::PeerId, NoiseOutput<core::Negotiated<C>>),
        (libp2p::PeerId, TlsStream<core::Negotiated<C>>),
    >|
     -> (PeerId, Box<dyn AsyncRW>) {
        match x {
            EitherOutput::First((p_id, out)) => (p_id, Box::new(out)),
            EitherOutput::Second((p_id, out)) => (p_id, Box::new(out)),
        }
    };

    let secure_upgrade = secure_upgrade.map_outbound(f).map_inbound(f);
    let authenticated = builder.authenticate(secure_upgrade);

    let mux_upgrade = match muxer_param.as_str() {
        "yamux" => EitherUpgrade::A(yamux::YamuxConfig::default()),
        "mplex" => EitherUpgrade::B(mplex::MplexConfig::default()),
        _ => panic!("Unsupported muxer"),
    };

    authenticated
        .multiplex(mux_upgrade)
        .timeout(Duration::from_secs(5))
        .boxed()
}

#[async_std::main]
async fn main() -> Result<()> {
    let local_key = identity::Keypair::generate_ed25519();
    let local_peer_id = PeerId::from(local_key.public());

    let client = TGClient::new_and_init().await.unwrap();

    let transport_param: String = client
        .run_parameters()
        .test_instance_params
        .get("transport")
        .unwrap()
        .parse()
        .unwrap();

    let secure_channel_param: String = client
        .run_parameters()
        .test_instance_params
        .get("security")
        .unwrap()
        .parse()
        .unwrap();

    let muxer_param: String = client
        .run_parameters()
        .test_instance_params
        .get("muxer")
        .unwrap()
        .parse()
        .unwrap();

    let boxed_transport = match transport_param.as_str() {
        "quic-v1" => {
            let builder =
                libp2p::quic::async_std::Transport::new(libp2p::quic::Config::new(&local_key))
                    .map(|(p, c), _| (p, StreamMuxerBox::new(c)));
            builder.boxed()
        }
        "tcp" => {
            let builder = libp2p::tcp::async_io::Transport::new(libp2p::tcp::Config::new())
                .upgrade(libp2p::core::upgrade::Version::V1Lazy);

            build_builder(
                builder,
                secure_channel_param,
                muxer_param,
                local_key.clone(),
            )
        }
        "ws" => {
            let builder = WsConfig::new(libp2p::tcp::async_io::Transport::new(
                libp2p::tcp::Config::new(),
            ))
            .upgrade(libp2p::core::upgrade::Version::V1Lazy);

            build_builder(
                builder,
                secure_channel_param,
                muxer_param,
                local_key.clone(),
            )
        }
        _ => panic!("Unsupported"),
    };

    let transport_kind = match transport_param.as_str() {
        "tcp" => TransportKind::Tcp,
        "ws" => TransportKind::WebSocket,
        "quic-v1" => TransportKind::Quic,
        _ => panic!("Unsupported"),
    };

    let swarm = OrphanRuleWorkaround(Swarm::with_async_std_executor(
        boxed_transport,
        ping::Behaviour::new(
            #[allow(deprecated)]
            // TODO: Fixing this deprecation requires https://github.com/libp2p/rust-libp2p/pull/3055.
            ping::Config::new()
                .with_interval(Duration::from_secs(1))
                .with_keep_alive(true),
        ),
        local_peer_id,
    ));

    run_ping(client, swarm, transport_kind).await?;

    Ok(())
}

struct OrphanRuleWorkaround(Swarm<ping::Behaviour>);

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
