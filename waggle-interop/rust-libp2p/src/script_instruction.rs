use std::error::Error;
use std::ffi::OsStr;
use std::fmt::Display;
use std::path::Path;

use byteorder::{ByteOrder, LittleEndian};
use libp2p::identity::Keypair;
use serde::{Deserialize, Serialize};

/// NodeID is a unique identifier for a node in the network.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeID(pub i32);

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

    #[serde(rename = "subscribeToTopic", rename_all = "camelCase")]
    SubscribeToTopic {
        #[serde(rename = "topicID")]
        topic_id: String,
    },

    #[serde(rename = "initWaggle", rename_all = "camelCase")]
    InitWaggle { waggle_params: Box<WaggleParams> },

    #[serde(rename = "addPiece", rename_all = "camelCase")]
    AddPiece {
        parts: u8,
        #[serde(rename = "topicID")]
        topic_id: String,
        #[serde(rename = "objectID")]
        object_id: u64,
    },

    #[serde(rename = "publish", rename_all = "camelCase")]
    Publish {
        #[serde(rename = "topicID")]
        topic_id: String,
        #[serde(rename = "objectID")]
        object_id: u64,
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

/// WaggleParams contains parameters for the Waggle protocol.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WaggleParams {
    pub publish_fanout: Option<usize>,
    pub gossip_fanout: Option<usize>,
}

