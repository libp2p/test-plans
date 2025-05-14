use serde::{Deserialize, Serialize};

/// NodeID is a unique identifier for a node in the network.
pub type NodeID = i32;

/// ScriptAction represents an action that can be executed in a script.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ScriptAction {
    #[serde(rename = "connect")]
    Connect {
        #[serde(rename = "connectTo")]
        connect_to: Vec<NodeID>,
    },

    #[serde(rename = "ifNodeIDEquals")]
    IfNodeIDEquals {
        #[serde(rename = "nodeID")]
        node_id: NodeID,
        action: Box<ScriptAction>,
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
}

/// ExperimentParams contains all parameters for an experiment.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentParams {
    #[serde(rename = "gossipSubParams")]
    pub gossip_sub_params: Option<GossipSubParams>,
    pub script: Vec<ScriptAction>,
}

/// GossipSubParams contains parameters for the GossipSub protocol.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct GossipSubParams {
    #[serde(rename = "D")]
    pub d: Option<i32>,
    #[serde(rename = "D_low")]
    pub d_low: Option<i32>,
    #[serde(rename = "D_high")]
    pub d_high: Option<i32>,
    #[serde(rename = "D_score")]
    pub d_score: Option<i32>,
    #[serde(rename = "D_out")]
    pub d_out: Option<i32>,
    #[serde(rename = "historyLength")]
    pub history_length: Option<i32>,
    #[serde(rename = "historyGossip")]
    pub history_gossip: Option<i32>,
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
    pub max_ihave_length: Option<i32>,
    #[serde(rename = "maxIHaveMessages")]
    pub max_ihave_messages: Option<i32>,
    #[serde(rename = "iWantFollowupTime")]
    pub iwant_followup_time: Option<f64>,
}
