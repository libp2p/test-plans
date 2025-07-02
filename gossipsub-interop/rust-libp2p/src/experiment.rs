use byteorder::{BigEndian, ByteOrder};
use futures::channel::mpsc;
use futures::{SinkExt, StreamExt};
use libp2p::gossipsub::{self, IdentTopic};
use libp2p::swarm::{NetworkBehaviour, SwarmEvent};
use libp2p::{identify, Swarm};
use slog::{error, info, Logger};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::time::sleep;

use crate::connector;
use crate::script_instruction::{ExperimentParams, NodeID, ScriptInstruction};

// Calculate message ID based on content (equivalent to Go's CalcID)
pub fn format_message_id(data: &[u8]) -> String {
    if data.len() >= 8 {
        format!("{}", BigEndian::read_u64(data))
    } else {
        // If data is too short, return a placeholder
        "invalid_message".to_string()
    }
}

#[derive(Debug)]
pub struct ValidationResult {
    peer_id: libp2p::PeerId,
    msg_id: gossipsub::MessageId,
    result: gossipsub::MessageAcceptance,
}

pub struct ScriptedNode {
    node_id: NodeID,
    swarm: Swarm<MyBehavior>,
    gossipsub_validation_rx: mpsc::Receiver<ValidationResult>,
    gossipsub_validation_tx: mpsc::Sender<ValidationResult>,
    stderr_logger: Logger,
    stdout_logger: Logger,
    topics: HashMap<String, IdentTopic>,
    start_time: Instant,
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
        let (gossipsub_validation_tx, gossipsub_validation_rx) = mpsc::channel(2);
        Self {
            node_id,
            swarm,
            stderr_logger,
            stdout_logger,
            topics: HashMap::new(),
            start_time,
            gossipsub_validation_rx,
            gossipsub_validation_tx,
        }
    }

    pub fn get_topic(&mut self, topic_str: &str) -> IdentTopic {
        if let Some(topic) = self.topics.get(topic_str) {
            topic.clone()
        } else {
            let topic = IdentTopic::new(topic_str);
            self.topics.insert(topic_str.to_string(), topic.clone());
            topic
        }
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
                            res = self.gossipsub_validation_rx.next() => {
                                if let Some(res) = res {
                                    info!(self.stdout_logger, "Validation Result"; "result" => format!("{:?}", res));

                                    self.swarm.behaviour_mut()
                                        .gossipsub
                                        .report_message_validation_result(
                                            &res.msg_id, &res.peer_id, res.result
                                        );
                                }
                            }
                            event = self.swarm.select_next_some() => {
                                // Process any messages that arrive during sleep
                                if let SwarmEvent::Behaviour(MyBehaviorEvent::Gossipsub(gossipsub::Event::Message {
                                    propagation_source: peer_id,
                                    message_id,
                                    message,
                                })) = event {
                                    if message.data.len() >= 8 {
                                        info!(self.stdout_logger, "Received Message";
                                            "topic" => message.topic.into_string(),
                                            "id" => format_message_id(&message.data),
                                            "from" => peer_id.to_string());
                                    }
                                    // Shadow doesn’t model CPU execution time,
                                    // instructions execute instantly in the simulations.
                                    // Usually in lighthouse blob verification takes ~5ms,
                                    // so calling `thread::sleep` aims at replicating the same behaviour.
                                    // See https://github.com/shadow/shadow/issues/2060 for more info.

                                    let mut tx = self.gossipsub_validation_tx.clone();
                                    tokio::spawn(async move {
                                        sleep(Duration::from_millis(5)).await;
                                        tx.send(ValidationResult {
                                            peer_id,
                                            msg_id: message_id,
                                            result: gossipsub::MessageAcceptance::Accept,
                                        }).await.unwrap();
                                    });
                                }
                            }
                        }
                    }
                }
            }
            ScriptInstruction::Publish {
                message_id,
                message_size_bytes,
                topic_id,
            } => {
                let topic = self.get_topic(&topic_id);

                info!(self.stderr_logger, "Publishing message {}", message_id);

                let mut msg = vec![0u8; message_size_bytes];
                BigEndian::write_u64(&mut msg, message_id);

                match self
                    .swarm
                    .behaviour_mut()
                    .gossipsub
                    .publish(topic, msg.clone())
                {
                    Ok(_) => {
                        info!(self.stderr_logger, "Published message {}", message_id);
                    }
                    Err(e) => {
                        error!(
                            self.stderr_logger,
                            "Failed to publish message {}: {}", message_id, e
                        );
                        return Err(Box::new(std::io::Error::other(e.to_string())));
                    }
                }
            }
            ScriptInstruction::SubscribeToTopic { topic_id } => {
                let topic = self.get_topic(&topic_id);

                match self.swarm.behaviour_mut().gossipsub.subscribe(&topic) {
                    Ok(_) => {
                        info!(self.stderr_logger, "Subscribed to topic {}", topic_id);
                    }
                    Err(e) => {
                        error!(
                            self.stderr_logger,
                            "Failed to subscribe to topic {}: {}", topic_id, e
                        );
                        return Err(Box::new(std::io::Error::other(e.to_string())));
                    }
                }
            }
            ScriptInstruction::InitGossipSub {
                gossip_sub_params: _,
            } => {
                // This is handled before node creation in main.rs, so we don't need to do anything here
                info!(
                    self.stderr_logger,
                    "InitGossipSub instruction already processed"
                );
            }
        }

        Ok(())
    }
}

#[derive(NetworkBehaviour)]
pub struct MyBehavior {
    pub gossipsub: gossipsub::Behaviour,
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

// Extract InitGossipSub parameters from script instructions
pub fn extract_gossipsub_params(
    script: &[ScriptInstruction],
    node_id: NodeID,
) -> Option<crate::script_instruction::GossipSubParams> {
    for instruction in script {
        match instruction {
            ScriptInstruction::InitGossipSub { gossip_sub_params } => {
                return Some(**gossip_sub_params);
            }
            ScriptInstruction::IfNodeIDEquals {
                node_id: instruction_node_id,
                instruction,
            } => {
                if *instruction_node_id == node_id {
                    if let ScriptInstruction::InitGossipSub { gossip_sub_params } =
                        instruction.as_ref()
                    {
                        return Some(**gossip_sub_params);
                    }
                }
            }
            _ => {}
        }
    }
    None
}
