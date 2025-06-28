use std::error::Error;
use std::ffi::OsStr;
use std::fmt::Display;
use std::{path::Path, time::Duration};

use byteorder::{ByteOrder, LittleEndian};
use libp2p::gossipsub::ConfigBuilder;
use libp2p::identity::Keypair;
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
    #[serde(rename = "connect")]
    Connect {
        #[serde(rename = "connectTo")]
        connect_to: Vec<NodeID>,
    },

    #[serde(rename = "ifNodeIDEquals")]
    IfNodeIDEquals {
        #[serde(rename = "nodeID")]
        node_id: NodeID,
        #[serde(rename = "instruction")]
        instruction: Box<ScriptInstruction>,
    },

    #[serde(rename = "waitUntil")]
    WaitUntil {
        #[serde(rename = "elapsedSeconds")]
        elapsed_seconds: u64,
    },

    #[serde(rename = "publish")]
    Publish {
        #[serde(rename = "messageID")]
        message_id: u64,
        #[serde(rename = "messageSizeBytes")]
        message_size_bytes: usize,
        #[serde(rename = "topicID")]
        topic_id: String,
    },

    #[serde(rename = "subscribeToTopic")]
    SubscribeToTopic {
        #[serde(rename = "topicID")]
        topic_id: String,
    },

    #[serde(rename = "initGossipSub")]
    InitGossipSub {
        #[serde(rename = "gossipSubParams")]
        gossip_sub_params: Box<GossipSubParams>,
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
pub struct GossipSubParams {
    #[serde(rename = "D")]
    pub d: Option<usize>,
    #[serde(rename = "D_low")]
    pub d_low: Option<usize>,
    #[serde(rename = "D_high")]
    pub d_high: Option<usize>,
    #[serde(rename = "D_score")]
    pub d_score: Option<usize>,
    #[serde(rename = "D_out")]
    pub d_out: Option<usize>,
    #[serde(rename = "historyLength")]
    pub history_length: Option<usize>,
    #[serde(rename = "historyGossip")]
    pub history_gossip: Option<usize>,
    #[serde(rename = "heartbeatInitialDelay")]
    pub heartbeat_initial_delay: Option<f64>,
    #[serde(rename = "heartbeatInterval")]
    pub heartbeat_interval: Option<f64>,
    #[serde(rename = "fanoutTTL")]
    pub fanout_ttl: Option<f64>,
    #[serde(rename = "mcacheLen")]
    pub mcache_len: Option<i32>,
    #[serde(rename = "mcacheGossip")]
    pub mcache_gossip: Option<i32>,
    #[serde(rename = "seenTTL")]
    pub seen_ttl: Option<f64>,
    #[serde(rename = "opportunisticGraftPeers")]
    pub opportunistic_graft_peers: Option<i32>,
    #[serde(rename = "opportunisticGraftTicks")]
    pub opportunistic_graft_ticks: Option<i32>,
    #[serde(rename = "opprotunisticGraftTicksBackoff")]
    pub opportunistic_graft_ticks_backoff: Option<i32>,
    #[serde(rename = "directConnectTicks")]
    pub direct_connect_ticks: Option<i32>,
    #[serde(rename = "directConnectTicksBackoff")]
    pub direct_connect_ticks_backoff: Option<i32>,
    #[serde(rename = "directConnectInitialDelay")]
    pub direct_connect_initial_delay: Option<f64>,
    #[serde(rename = "pruneBackoff")]
    pub prune_backoff: Option<f64>,
    #[serde(rename = "floodPublish")]
    pub flood_publish: Option<bool>,
    #[serde(rename = "graftFloodThreshold")]
    pub graft_flood_threshold: Option<i32>,
    #[serde(rename = "validateMessageDeliveriesWindow")]
    pub validate_message_deliveries_window: Option<f64>,
    #[serde(rename = "scoreInspectPeersCacheSize")]
    pub score_inspect_peers_cache_size: Option<i32>,
    #[serde(rename = "maxIHaveLength")]
    pub max_ihave_length: Option<usize>,
    #[serde(rename = "maxIHaveMessages")]
    pub max_ihave_messages: Option<usize>,
    #[serde(rename = "iWantFollowupTime")]
    pub iwant_followup_time: Option<f64>,
}

impl From<GossipSubParams> for ConfigBuilder {
    fn from(params: GossipSubParams) -> Self {
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
        if let Some(heartbeat_initial_delay) = params.heartbeat_initial_delay {
            builder.heartbeat_initial_delay(Duration::from_nanos(heartbeat_initial_delay as u64));
        }
        if let Some(heartbeat_interval) = params.heartbeat_interval {
            builder.heartbeat_interval(Duration::from_nanos(heartbeat_interval as u64));
        }
        if let Some(fanout_ttl) = params.fanout_ttl {
            builder.fanout_ttl(Duration::from_nanos(fanout_ttl as u64));
        }
        if let Some(history_length) = params.history_length {
            builder.history_length(history_length);
        }
        if let Some(history_gossip) = params.history_gossip {
            builder.history_gossip(history_gossip);
        }
        if let Some(flood_publish) = params.flood_publish {
            builder.flood_publish(flood_publish);
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

        // Just disable this by using a large value
        builder.max_transmit_size(1 << 30);
        builder
    }
}
