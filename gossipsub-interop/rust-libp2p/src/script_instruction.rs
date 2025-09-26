use std::error::Error;
use std::ffi::OsStr;
use std::fmt::Display;
use std::{path::Path, time::Duration};

use byteorder::{ByteOrder, LittleEndian};
use libp2p::identity::Keypair;
use libp2p_gossipsub::ConfigBuilder;
use serde::{Deserialize, Serialize};

/// NodeID is a unique identifier for a node in the network.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeID(i32);

impl NodeID {
    /// Generate a node from the hostname
    pub fn new() -> Result<Self, Box<dyn Error>> {
        let hostname = hostname::get()?.to_string_lossy().into_owned();

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
        Ok(NodeID(id_str.parse::<i32>()?))
    }
}

impl Display for NodeID {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<NodeID> for Keypair {
    fn from(value: NodeID) -> Self {
        // Create a deterministic seed based on the node ID
        let mut seed = [0u8; 32];
        LittleEndian::write_i32(&mut seed[0..4], value.0);

        // Create a keypair from the seed
        Keypair::ed25519_from_bytes(seed).expect("Failed to create keypair")
    }
}
/// ScriptInstruction represents an instruction that can be executed in a script.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ScriptInstruction {
    #[serde(rename = "connect", rename_all = "camelCase")]
    Connect { connect_to: Vec<NodeID> },

    #[serde(rename = "ifNodeIDEquals", rename_all = "camelCase")]
    IfNodeIDEquals {
        #[serde(rename = "nodeID")]
        node_id: NodeID,
        instruction: Box<ScriptInstruction>,
    },

    #[serde(rename = "waitUntil", rename_all = "camelCase")]
    WaitUntil { elapsed_seconds: u64 },

    #[serde(rename = "publish", rename_all = "camelCase")]
    Publish {
        #[serde(rename = "messageID")]
        message_id: u64,
        message_size_bytes: usize,
        #[serde(rename = "topicID")]
        topic_id: String,
    },

    #[serde(rename = "subscribeToTopic", rename_all = "camelCase")]
    SubscribeToTopic {
        #[serde(rename = "topicID")]
        topic_id: String,
    },

    #[serde(rename = "setTopicValidationDelay", rename_all = "camelCase")]
    SetTopicValidationDelay {
        #[serde(rename = "topicID")]
        topic_id: String,
        delay_seconds: f64,
    },

    #[serde(rename = "initGossipSub", rename_all = "camelCase")]
    InitGossipSub {
        gossip_sub_params: Box<GossipSubParams>,
    },
    #[serde(rename = "addPartialMessage", rename_all = "camelCase")]
    AddPartialMessage {
        #[serde(rename = "r#type")]
        message_type: String,
        parts: u8,
        #[serde(rename = "topicID")]
        topic_id: String,
        #[serde(rename = "groupID")]
        group_id: u64,
    },
    #[serde(rename = "publishPartial", rename_all = "camelCase")]
    PublishPartial {
        #[serde(rename = "r#type")]
        message_type: String,
        topic_id: String,
        #[serde(rename = "groupID")]
        group_id: u64,
    },
}

/// ExperimentParams contains all parameters for an experiment.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentParams {
    pub script: Vec<ScriptInstruction>,
}

impl ExperimentParams {
    pub fn from_json_file<P: AsRef<Path>>(path: P) -> Result<Self, Box<dyn Error>> {
        let path = path.as_ref();

        if path.extension() != Some(OsStr::new("json")) {
            return Err("Params file must be a .json file".into());
        }

        let contents: String = std::fs::read_to_string(path)?;

        serde_json::from_str(&contents).map_err(Into::into)
    }
}

/// GossipSubParams contains parameters for the GossipSub protocol.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub struct GossipSubParams {
    #[serde(rename = "D")]
    pub d: Option<usize>,
    #[serde(rename = "Dlo")]
    pub d_low: Option<usize>,
    #[serde(rename = "Dhi")]
    pub d_high: Option<usize>,
    #[serde(rename = "Dscore")]
    pub d_score: Option<usize>,
    #[serde(rename = "Dout")]
    pub d_out: Option<usize>,
    pub history_length: Option<usize>,
    pub history_gossip: Option<usize>,
    #[serde(rename = "Dlazy")]
    pub d_lazy: Option<usize>,
    pub gossip_factor: Option<f64>,
    pub gossip_retransmission: Option<usize>,
    pub heartbeat_initial_delay: Option<f64>,
    pub heartbeat_interval: Option<f64>,
    pub slow_heartbeat_warning: Option<f64>,
    #[serde(rename = "FanoutTTL")]
    pub fanout_ttl: Option<f64>,
    pub prune_peers: Option<usize>,
    pub prune_backoff: Option<f64>,
    pub unsubscribe_backoff: Option<f64>,
    pub connectors: Option<usize>,
    pub max_pending_connections: Option<usize>,
    pub connection_timeout: Option<f64>,
    pub direct_connect_ticks: Option<i32>,
    pub direct_connect_initial_delay: Option<f64>,
    pub opportunistic_graft_ticks: Option<u64>,
    pub opportunistic_graft_peers: Option<usize>,
    pub graft_flood_threshold: Option<f64>,
    #[serde(rename = "MaxIHaveLength")]
    pub max_ihave_length: Option<usize>,
    #[serde(rename = "MaxIHaveMessages")]
    pub max_ihave_messages: Option<usize>,
    #[serde(rename = "MaxIDontWantLength")]
    pub max_idont_want_length: Option<usize>,
    #[serde(rename = "MaxIDontWantMessages")]
    pub max_idont_want_messages: Option<usize>,
    #[serde(rename = "IWantFollowupTime")]
    pub iwant_followup_time: Option<f64>,
    #[serde(rename = "IDontWantMessageThreshold")]
    pub idont_want_message_threshold: Option<usize>,
    #[serde(rename = "IDontWantMessageTTL")]
    pub idont_want_message_ttl: Option<f64>,
}

impl From<GossipSubParams> for ConfigBuilder {
    fn from(params: GossipSubParams) -> Self {
        // Log warnings for unsupported parameters
        if params.slow_heartbeat_warning.is_some() {
            eprintln!("Warning: slow_heartbeat_warning parameter is not supported by rust-libp2p gossipsub");
        }
        if params.connection_timeout.is_some() {
            eprintln!(
                "Warning: connection_timeout parameter is not supported by rust-libp2p gossipsub"
            );
        }
        if params.direct_connect_ticks.is_some() {
            eprintln!(
                "Warning: direct_connect_ticks parameter is not supported by rust-libp2p gossipsub"
            );
        }
        if params.direct_connect_initial_delay.is_some() {
            eprintln!("Warning: direct_connect_initial_delay parameter is not supported by rust-libp2p gossipsub");
        }
        if params.connectors.is_some() {
            eprintln!("Warning: connectors parameter is not supported by rust-libp2p gossipsub");
        }
        if params.max_pending_connections.is_some() {
            eprintln!("Warning: max_pending_connections parameter is not supported by rust-libp2p gossipsub");
        }
        if params.max_idont_want_length.is_some() {
            eprintln!("Warning: max_idont_want_length parameter is not supported by rust-libp2p gossipsub");
        }
        if params.max_idont_want_messages.is_some() {
            eprintln!("Warning: max_idont_want_messages parameter is not supported by rust-libp2p gossipsub");
        }
        if params.idont_want_message_ttl.is_some() {
            eprintln!("Warning: idont_want_message_ttl parameter is not supported by rust-libp2p gossipsub");
        }

        let mut builder = ConfigBuilder::default();
        if let Some(d) = params.d {
            builder.mesh_n(d);
        }
        if let Some(d_low) = params.d_low {
            builder.mesh_n_low(d_low);
        }
        if let Some(d_high) = params.d_high {
            builder.mesh_n_high(d_high);
        }
        if let Some(d_score) = params.d_score {
            builder.retain_scores(d_score);
        }
        if let Some(d_out) = params.d_out {
            builder.mesh_outbound_min(d_out);
        }
        if let Some(history_length) = params.history_length {
            builder.history_length(history_length);
        }
        if let Some(history_gossip) = params.history_gossip {
            builder.history_gossip(history_gossip);
        }
        if let Some(d_lazy) = params.d_lazy {
            builder.gossip_lazy(d_lazy);
        }
        if let Some(gossip_factor) = params.gossip_factor {
            builder.gossip_factor(gossip_factor);
        }
        if let Some(gossip_retransmission) = params.gossip_retransmission {
            builder.gossip_retransimission(gossip_retransmission as u32);
        }
        if let Some(heartbeat_initial_delay) = params.heartbeat_initial_delay {
            builder.heartbeat_initial_delay(Duration::from_nanos(heartbeat_initial_delay as u64));
        }
        if let Some(heartbeat_interval) = params.heartbeat_interval {
            builder.heartbeat_interval(Duration::from_nanos(heartbeat_interval as u64));
        }
        if let Some(fanout_ttl) = params.fanout_ttl {
            builder.fanout_ttl(Duration::from_nanos(fanout_ttl as u64));
        }
        if let Some(prune_peers) = params.prune_peers {
            builder.prune_peers(prune_peers);
        }
        if let Some(prune_backoff) = params.prune_backoff {
            builder.prune_backoff(Duration::from_nanos(prune_backoff as u64));
        }
        if let Some(unsubscribe_backoff) = params.unsubscribe_backoff {
            builder.unsubscribe_backoff(Duration::from_nanos(unsubscribe_backoff as u64));
        }
        if let Some(opportunistic_graft_ticks) = params.opportunistic_graft_ticks {
            builder.opportunistic_graft_ticks(opportunistic_graft_ticks);
        }
        if let Some(opportunistic_graft_peers) = params.opportunistic_graft_peers {
            builder.opportunistic_graft_peers(opportunistic_graft_peers);
        }
        if let Some(graft_flood_threshold) = params.graft_flood_threshold {
            builder.graft_flood_threshold(Duration::from_nanos(graft_flood_threshold as u64));
        }
        if let Some(max_ihave_length) = params.max_ihave_length {
            builder.max_ihave_length(max_ihave_length);
        }
        if let Some(max_ihave_messages) = params.max_ihave_messages {
            builder.max_ihave_messages(max_ihave_messages);
        }
        if let Some(iwant_followup_time) = params.iwant_followup_time {
            builder.iwant_followup_time(Duration::from_nanos(iwant_followup_time as u64));
        }
        if let Some(idont_want_message_threshold) = params.idont_want_message_threshold {
            builder.idontwant_message_size_threshold(idont_want_message_threshold);
        }

        // Just disable this by using a large value
        builder.max_transmit_size(1 << 30);
        builder
    }
}
