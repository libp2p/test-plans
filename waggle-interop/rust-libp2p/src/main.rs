use clap::Parser;
use libp2p::{
    core::upgrade, identify, noise, tcp, yamux, PeerId, Swarm, Transport,
};
use slog::{o, Drain, FnValue, Logger, PushFnValue, Record};
use std::num::NonZeroUsize;
use std::time::Instant;
use tracing_subscriber::{layer::SubscriberExt, Layer};

mod bitmap;
mod connector;
mod experiment;
mod key;
mod script_instruction;

use experiment::{MyBehavior, run_experiment};
use script_instruction::{ExperimentParams, NodeID};
use waggle::config::{Config, TopicConfig};

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

fn build_waggle_config(params: Option<&script_instruction::WaggleParams>) -> Config {
    let mut config = Config::default();
    let Some(params) = params else {
        return config;
    };

    let mut topic_config = TopicConfig::default();
    if let Some(publish_fanout) = params.publish_fanout {
        topic_config = topic_config.set_publish_fanout(
            NonZeroUsize::new(publish_fanout).expect("publish_fanout must be non-zero"),
        );
    }
    if let Some(gossip_fanout) = params.gossip_fanout {
        topic_config = topic_config.set_gossip_fanout(
            NonZeroUsize::new(gossip_fanout).expect("gossip_fanout must be non-zero"),
        );
    }
    config = config.set_default_topic_config(topic_config);
    config
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    let (stderr_logger, stdout_logger) = create_logger();

    let subscriber = tracing_subscriber::registry().with(
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
    let local_key = key::node_priv_key(node_id);
    let local_peer_id = PeerId::from(local_key.public());
    slog::info!(stderr_logger, "Local peer id: {}", local_peer_id);
    slog::info!(stderr_logger, "Node ID: {}", node_id);
    // Create a transport
    let transport = tcp::tokio::Transport::default()
        .upgrade(upgrade::Version::V1)
        .authenticate(noise::Config::new(&local_key)?)
        .multiplex(yamux::Config::default())
        .boxed();

    // Create waggle configuration
    let waggle_params = experiment::extract_waggle_params(&params.script, node_id);
    if waggle_params.is_some() {
        slog::info!(
            stderr_logger,
            "Applying Waggle params from InitWaggle instruction"
        );
    }
    let waggle_config = build_waggle_config(waggle_params.as_ref());
    let waggle = waggle::behaviour::Behaviour::new(waggle_config);

    let identify = identify::Behaviour::new(identify::Config::new(
        "/interop/1.0.0".into(),
        local_key.public(),
    ));
    let behavior = MyBehavior {
        waggle,
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