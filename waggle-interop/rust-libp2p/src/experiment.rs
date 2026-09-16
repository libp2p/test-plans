use byteorder::BigEndian;
use byteorder::ByteOrder;
use futures::StreamExt;
use libp2p::swarm::{NetworkBehaviour, SwarmEvent};
use libp2p::{identify, Swarm};
use slog::{error, info, Logger};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use waggle::behaviour;
use waggle::shard::Shard;

use crate::bitmap::Bitmap;
use crate::connector;
use crate::script_instruction::{ExperimentParams, NodeID, ScriptInstruction, WaggleParams};

// Calculate object id based on content (equivalent to Go's CalcID)
pub fn format_object_id(data: &[u8]) -> String {
    if data.len() >= 8 {
        format!("{}", BigEndian::read_u64(data))
    } else {
        // If data is too short, return a placeholder
        "invalid_object".to_string()
    }
}

pub struct ScriptedNode {
    node_id: NodeID,
    swarm: Swarm<MyBehavior>,
    stderr_logger: Logger,
    stdout_logger: Logger,
    topics: HashMap<String, Vec<u8>>,
    start_time: Instant,
    partials: HashMap<String, HashMap<[u8; 8], Bitmap>>,
}

impl ScriptedNode {
    pub fn new(
        node_id: NodeID,
        swarm: Swarm<MyBehavior>,
        stderr_logger: Logger,
        stdout_logger: Logger,
        start_time: Instant,
    ) -> Self {
        info!(stdout_logger, "PeerID"; "id" => %swarm.local_peer_id(), "node_id" => %node_id);
        Self {
            node_id,
            swarm,
            stderr_logger,
            stdout_logger,
            topics: HashMap::new(),
            start_time,
            partials: HashMap::new(),
        }
    }

    fn get_topic(&mut self, topic_str: &str) -> Vec<u8> {
        if let Some(topic) = self.topics.get(topic_str) {
            topic.clone()
        } else {
            let topic = topic_str.as_bytes().to_vec();
            self.topics.insert(topic_str.to_string(), topic.clone());
            topic
        }
    }

    fn get_or_create_partial(&mut self, topic_id: &str, object_id: [u8; 8]) -> &mut Bitmap {
        self.partials
            .entry(topic_id.to_string())
            .or_default()
            .entry(object_id)
            .or_insert_with(|| Bitmap::new(object_id))
    }

    fn publish_partial(&mut self, topic_id: &str, partial: &Bitmap) {
        let topic = self.get_topic(topic_id);
        if let Err(e) = self
            .swarm
            .behaviour_mut()
            .waggle
            .publish(topic, partial.clone())
        {
            // Publishing can fail when no peers are subscribed to the topic
            // or when all eligible peers already have everything. Neither is
            // a fatal error for the simulation.
            info!(
                self.stderr_logger,
                "Publish partial to topic {topic_id} returned {e}"
            );
        }
    }

    async fn handle_received(
        &mut self,
        topic_id: Vec<u8>,
        peer_id: libp2p::PeerId,
        received: waggle::handler::Received,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let topic_str = String::from_utf8_lossy(&topic_id).into_owned();
        let object_id: [u8; 8] = received
            .object_id
            .try_into()
            .map_err(|_| "Invalid object_id length")?;

        let mut partial = self.get_or_create_partial(&topic_str, object_id).clone();

        let before_extension = partial.metadata().as_slice().to_vec();
        if let Some(pieces) = received.pieces {
            if !pieces.is_empty() {
                info!(self.stderr_logger, "new data len is {}", pieces.len());
                partial.extend_from_pieces(&pieces)?;
            }
        }
        let after_extension = partial.metadata().as_slice().to_vec();

        let mut should_republish = false;
        if before_extension != after_extension {
            info!(
                self.stderr_logger,
                "Got new data. Will republish. {before_extension:?} {after_extension:?}"
            );
            info!(
                self.stdout_logger,
                "Received Message";
                "id" => format_object_id(&object_id),
                "topic" => &topic_str,
                "from" => peer_id.to_string(),
            );
            if partial.complete() {
                info!(
                    self.stdout_logger,
                    "All parts received";
                    "object_id" => format_object_id(&object_id),
                    "from" => peer_id.to_string(),
                );
            }

            should_republish = true;
        }
        if !should_republish
            && received
                .metadata
                .as_ref()
                .is_some_and(|m| m.as_slice() != after_extension.as_slice())
        {
            info!(
                self.stderr_logger,
                "I have something the peer doesn't or vice versa."
            );
            should_republish = true;
        }
        info!(self.stderr_logger, "I have {:?}", after_extension);
        info!(self.stderr_logger, "Peer has {:?}", received.metadata);

        if should_republish {
            self.partials
                .entry(topic_str.clone())
                .or_default()
                .insert(object_id, partial.clone());
            self.publish_partial(&topic_str, &partial);
        }

        Ok(())
    }

    pub async fn run_instruction(
        &mut self,
        instruction: ScriptInstruction,
    ) -> Result<(), Box<dyn std::error::Error>> {
        match instruction {
            ScriptInstruction::Connect { connect_to } => {
                for target_node_id in connect_to {
                    match connector::connect_to(&mut self.swarm, target_node_id).await {
                        Ok(_) => {
                            info!(self.stderr_logger, "Connected to node {}", target_node_id);
                        }
                        Err(e) => {
                            error!(
                                self.stderr_logger,
                                "Failed to connect to node {}: {}", target_node_id, e
                            );
                            return Err(e.into());
                        }
                    }
                }
                info!(
                    self.stderr_logger,
                    "Node {} connected to peers", self.node_id
                );
            }
            ScriptInstruction::IfNodeIDEquals {
                node_id,
                instruction,
            } => {
                if node_id == self.node_id {
                    Box::pin(self.run_instruction(*instruction)).await?;
                }
            }
            ScriptInstruction::WaitUntil { elapsed_seconds } => {
                let target_time = self.start_time + Duration::from_secs(elapsed_seconds);
                let now = Instant::now();

                if now < target_time {
                    let wait_time = target_time.duration_since(now);
                    info!(
                        self.stderr_logger,
                        "Waiting {:?} (until elapsed: {}s)", wait_time, elapsed_seconds
                    );

                    // Create a timeout future
                    let mut timeout = Box::pin(sleep(wait_time));

                    // Process events while waiting for the timeout
                    loop {
                        tokio::select! {
                            _ = &mut timeout => {
                                // Timeout complete, we can continue
                                break;
                            }
                            event = self.swarm.select_next_some() => {
                                // Process any messages that arrive during sleep
                                match event {
                                    SwarmEvent::Behaviour(MyBehaviorEvent::Waggle(
                                        behaviour::Event::Received { topic_id, peer_id, received },
                                    )) => {
                                        if let Err(e) = self.handle_received(topic_id, peer_id, received).await {
                                            error!(self.stderr_logger, "Failed to handle received piece: {}", e);
                                        }
                                    }
                                    SwarmEvent::Behaviour(MyBehaviorEvent::Waggle(ev)) => {
                                        info!(self.stderr_logger, "Waggle event: {ev:?}")
                                    }
                                    ev => {
                                        info!(self.stderr_logger, "Some other event, {:?}", ev)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ScriptInstruction::SubscribeToTopic { topic_id } => {
                let topic = self.get_topic(&topic_id);

                match self.swarm.behaviour_mut().waggle.subscribe(topic) {
                    true => {
                        info!(self.stderr_logger, "Subscribed to topic {}", topic_id);
                    }
                    false => {
                        info!(
                            self.stderr_logger,
                            "Already subscribed to topic {}", topic_id
                        );
                    }
                }
            }
            ScriptInstruction::InitWaggle { waggle_params: _ } => {
                // This is handled before node creation in main.rs, so we don't need to do anything here
                info!(
                    self.stderr_logger,
                    "InitWaggle instruction already processed"
                );
            }
            ScriptInstruction::AddPiece {
                parts,
                topic_id,
                object_id,
            } => {
                let object_id_bytes = object_id.to_be_bytes();
                let mut partial = self
                    .get_or_create_partial(&topic_id, object_id_bytes)
                    .clone();
                info!(
                    self.stderr_logger,
                    "partial message for object {object_id:?} parts {parts:?}"
                );
                partial.fill_parts(parts);
                let avail = partial.metadata();
                info!(self.stderr_logger, "available parts: {avail:?}");
                if avail.as_slice() == vec![255] {
                    info!(
                        self.stdout_logger,
                        "All parts received";
                        "object_id" => format_object_id(&object_id_bytes),
                    );
                }
                self.partials
                    .entry(topic_id)
                    .or_default()
                    .insert(object_id_bytes, partial);
            }
            ScriptInstruction::Publish {
                topic_id,
                object_id,
            } => {
                let object_id_bytes = object_id.to_be_bytes();
                let partial = self
                    .partials
                    .get(&topic_id)
                    .and_then(|topic_partials| topic_partials.get(&object_id_bytes))
                    .ok_or(format!(
                        "Topic {topic_id} and object {object_id:?} doesn't exist"
                    ))?
                    .clone();
                info!(
                    self.stdout_logger,
                    "Publish Partial called";
                    "object_id" => format_object_id(&object_id_bytes),
                    "topic_id" => format!("{topic_id:?}"),
                );
                self.publish_partial(&topic_id, &partial);
            }
        }

        Ok(())
    }
}

#[derive(NetworkBehaviour)]
pub struct MyBehavior {
    pub waggle: waggle::behaviour::Behaviour,
    pub identify: identify::Behaviour,
}

pub async fn run_experiment(
    start_time: Instant,
    stderr_logger: Logger,
    stdout_logger: Logger,
    swarm: Swarm<MyBehavior>,
    node_id: NodeID,
    params: ExperimentParams,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut node = ScriptedNode::new(
        node_id,
        swarm,
        stderr_logger.clone(),
        stdout_logger.clone(),
        start_time,
    );
    for instruction in params.script {
        node.run_instruction(instruction).await?;
    }
    Ok(())
}

// Extract InitWaggle parameters from script instructions
pub fn extract_waggle_params(
    script: &[ScriptInstruction],
    node_id: NodeID,
) -> Option<WaggleParams> {
    for instruction in script {
        match instruction {
            ScriptInstruction::InitWaggle { waggle_params } => {
                return Some(**waggle_params);
            }
            ScriptInstruction::IfNodeIDEquals {
                node_id: instruction_node_id,
                instruction,
            } => {
                if *instruction_node_id == node_id {
                    if let ScriptInstruction::InitWaggle { waggle_params } = instruction.as_ref() {
                        return Some(**waggle_params);
                    }
                }
            }
            _ => {}
        }
    }
    None
}

