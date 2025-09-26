use clap::Parser;
use libp2p::{
    core::upgrade, identify, identity::Keypair, noise, tcp, yamux, PeerId, Swarm, Transport,
};
use libp2p_gossipsub::{self, MessageAuthenticity, MessageId, ValidationMode};
use slog::{o, Drain, FnValue, Logger, PushFnValue, Record};
use std::time::Instant;
use tracing_subscriber::{layer::SubscriberExt, Layer};

mod bitmap;
mod connector;
mod experiment;
mod log_filter;
mod script_instruction;

use experiment::{run_experiment, MyBehavior};
use script_instruction::{ExperimentParams, NodeID};

#[derive(Parser, Debug)]
#[clap(author, version, about)]
struct Args {
    /// Path to the params file
    #[clap(long, value_name = "FILE")]
    params: String,
}

fn create_logger() -> (Logger, Logger) {
    // Create stderr logger for most messages
    let stderr_drain = slog_json::Json::new(std::io::stderr())
        .add_key_value(o!(
            "time" => FnValue(move |_ : &slog::Record| {
                    time::OffsetDateTime::now_utc()
                    .format(&time::format_description::well_known::Rfc3339)
                    .ok()
            }),
            "level" => FnValue(move |rinfo : &Record| {
                rinfo.level().as_short_str()
            }),
            "msg" => PushFnValue(move |record : &Record, ser| {
                ser.emit(record.msg())
            }),
        ))
        .build()
        .fuse();
    let stderr_drain = slog_async::Async::new(stderr_drain).build().fuse();
    let stderr_logger = slog::Logger::root(stderr_drain, o!());

    // Create stdout logger for special messages
    let stdout_drain = slog_json::Json::new(std::io::stdout())
        .add_key_value(o!(
            "time" => FnValue(move |_ : &slog::Record| {
                    time::OffsetDateTime::now_utc()
                    .format(&time::format_description::well_known::Rfc3339)
                    .ok()
            }),
            "level" => FnValue(move |rinfo : &Record| {
                rinfo.level().as_short_str()
            }),
            "msg" => PushFnValue(move |record : &Record, ser| {
                ser.emit(record.msg())
            }),
        ))
        .build()
        .fuse();
    let stdout_drain = slog_async::Async::new(stdout_drain).build().fuse();
    let stdout_logger = slog::Logger::root(stdout_drain, o!());

    (stderr_logger, stdout_logger)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let (stderr_logger, stdout_logger) = create_logger();

    // Create a custom layer for intercepting duplicate message logs
    let dup_message_layer = log_filter::DuplicateMessageLayer::new(stdout_logger.clone());

    // Create and set the tracing subscriber with our custom layer
    let subscriber = tracing_subscriber::registry()
        .with(dup_message_layer.with_filter(log_filter::gossipsub_filter()))
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_ansi(false)
                .with_filter(tracing_subscriber::EnvFilter::from_default_env()),
        );

    tracing::subscriber::set_global_default(subscriber).expect("setting default subscriber failed");

    let start_time = Instant::now();
    // Load experiment parameters
    let params = ExperimentParams::from_json_file(&args.params)?;
    // Get the node ID from hostname
    let node_id = NodeID::new()?;
    // Create identity key from node ID
    let local_key: Keypair = node_id.into();
    let local_peer_id = PeerId::from(local_key.public());
    slog::info!(stderr_logger, "Local peer id: {}", local_peer_id);
    slog::info!(stderr_logger, "Node ID: {}", node_id);
    // Create a transport
    let transport = tcp::tokio::Transport::default()
        .upgrade(upgrade::Version::V1)
        .authenticate(noise::Config::new(&local_key)?)
        .multiplex(yamux::Config::default())
        .boxed();

    // Create gossipsub configuration
    let mut config_builder = match experiment::extract_gossipsub_params(&params.script, node_id) {
        Some(params) => {
            slog::info!(
                stderr_logger,
                "Applying GossipSub params from InitGossipSub instruction"
            );
            params.into()
        }
        None => libp2p_gossipsub::ConfigBuilder::default(),
    };
    config_builder
        .validation_mode(ValidationMode::Anonymous)
        // Custom message ID function similar to Go implementation
        .validate_messages()
        .message_id_fn(|message| MessageId::from(&message.data[0..8]));

    // Create gossipsub configuration
    let gossipsub_config = config_builder.build().expect("Valid gossipsub config");
    // Create gossipsub behavior
    let gossipsub =
        libp2p_gossipsub::Behaviour::new(MessageAuthenticity::Anonymous, gossipsub_config)?;
    let identify = identify::Behaviour::new(identify::Config::new(
        "/interop/1.0.0".into(),
        local_key.public(),
    ));
    let behavior = MyBehavior {
        gossipsub,
        identify,
    };
    // Build swarm
    let mut swarm = Swarm::new(
        transport,
        behavior,
        local_peer_id,
        libp2p::swarm::Config::with_tokio_executor(),
    );
    // Listen on all interfaces
    swarm.listen_on("/ip4/0.0.0.0/tcp/9000".parse()?)?;
    // Run the experiment
    run_experiment(
        start_time,
        stderr_logger,
        stdout_logger,
        swarm,
        node_id,
        params,
    )
    .await?;

    Ok(())
}
