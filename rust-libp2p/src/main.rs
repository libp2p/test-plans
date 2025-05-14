use clap::Parser;
use libp2p::{
    core::upgrade,
    gossipsub::{self, MessageAuthenticity, ValidationMode},
    identify, noise, tcp, yamux, PeerId, Swarm, Transport,
};
use slog::{o, Drain, FnValue, Logger, PushFnValue, Record};
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::time::Instant;
use tracing_subscriber::Layer;

mod connector;
mod experiment;
mod key;
mod log_filter;
mod script_action;

use connector::ShadowConnector;
use experiment::{run_experiment, MyBehavior};
use key::node_priv_key;
use script_action::{ExperimentParams, NodeID};

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

fn read_params(path: &str) -> Result<ExperimentParams, Box<dyn std::error::Error>> {
    if !path.ends_with(".json") {
        return Err("Params file must be a .json file".into());
    }

    let path = Path::new(path);
    if !path.exists() {
        return Err("Params file does not exist".into());
    }

    let mut file = File::open(path)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;

    let params: ExperimentParams = serde_json::from_str(&contents)?;
    Ok(params)
}

// Apply gossipsub parameters from the config file to the gossipsub config
fn apply_gossipsub_params(
    config: &mut gossipsub::ConfigBuilder,
    params: &script_action::GossipSubParams,
) {
    if let Some(d) = params.d {
        config.mesh_n(d as usize);
    }
    if let Some(d_low) = params.d_low {
        config.mesh_n_low(d_low as usize);
    }
    if let Some(d_high) = params.d_high {
        config.mesh_n_high(d_high as usize);
    }
    if let Some(heartbeat_initial_delay) = params.heartbeat_initial_delay {
        config.heartbeat_initial_delay(std::time::Duration::from_secs_f64(heartbeat_initial_delay));
    }
    if let Some(heartbeat_interval) = params.heartbeat_interval {
        config.heartbeat_interval(std::time::Duration::from_secs_f64(heartbeat_interval));
    }
    if let Some(fanout_ttl) = params.fanout_ttl {
        config.fanout_ttl(std::time::Duration::from_secs_f64(fanout_ttl));
    }
    if let Some(history_length) = params.history_length {
        config.history_length(history_length as usize);
    }
    if let Some(history_gossip) = params.history_gossip {
        config.history_gossip(history_gossip as usize);
    }
    if let Some(flood_publish) = params.flood_publish {
        config.flood_publish(flood_publish);
    }
    if let Some(max_ihave_length) = params.max_ihave_length {
        config.max_ihave_length(max_ihave_length as usize);
    }
    if let Some(max_ihave_messages) = params.max_ihave_messages {
        config.max_ihave_messages(max_ihave_messages as usize);
    }
    if let Some(iwant_followup_time) = params.iwant_followup_time {
        config.iwant_followup_time(std::time::Duration::from_secs_f64(iwant_followup_time));
    }

    // Just disable this by using a large value
    config.max_transmit_size(1 << 30);
}

// Get the node_id from hostname
fn get_node_id() -> Result<NodeID, Box<dyn std::error::Error>> {
    let hostname = hostname::get()?.into_string().unwrap_or_default();

    // Parse "nodeX" format
    let mut chars = hostname.chars();
    // Skip "node" prefix
    for _ in 0..4 {
        if chars.next().is_none() {
            return Err("Invalid hostname format".into());
        }
    }
    // Parse remaining digits as node ID
    let id_str: String = chars.collect();
    let node_id = id_str.parse::<NodeID>()?;
    Ok(node_id)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let (stderr_logger, stdout_logger) = create_logger();

    // Create a custom layer for intercepting duplicate message logs
    let dup_message_layer = log_filter::DuplicateMessageLayer::new(stdout_logger.clone());

    // Create and set the tracing subscriber with our custom layer
    use tracing_subscriber::layer::SubscriberExt;

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
    let params = read_params(&args.params)?;
    // Get the node ID from hostname
    let node_id = get_node_id()?;
    // Create identity key from node ID
    let local_key = node_priv_key(node_id);
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
    let mut config_builder = gossipsub::ConfigBuilder::default();
    config_builder
        .validation_mode(ValidationMode::Anonymous)
        .message_id_fn(experiment::message_id_fn);
    // Apply custom params if provided
    if let Some(params) = &params.gossip_sub_params {
        apply_gossipsub_params(&mut config_builder, params);
    }
    // Create gossipsub configuration
    let gossipsub_config = config_builder.build().expect("Valid gossipsub config");
    // Create gossipsub behavior
    let gossipsub = gossipsub::Behaviour::new(MessageAuthenticity::Anonymous, gossipsub_config)?;
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
    // Setup connector
    let connector = ShadowConnector;
    // Run the experiment
    run_experiment(
        start_time,
        stderr_logger,
        stdout_logger,
        swarm,
        node_id,
        connector,
        params,
    )
    .await?;

    Ok(())
}
