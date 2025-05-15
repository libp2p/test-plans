use byteorder::{BigEndian, ByteOrder};
use futures::StreamExt;
use libp2p::gossipsub::{self, IdentTopic, MessageId};
use libp2p::swarm::NetworkBehaviour;
use libp2p::{identify, Swarm};
use slog::{error, info, Logger};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::time::sleep;

use crate::connector::HostConnector;
use crate::script_action::{ExperimentParams, NodeID, ScriptAction};

// Calculate message ID based on content (equivalent to Go's CalcID)
pub fn calc_id(data: &[u8]) -> String {
    if data.len() >= 8 {
        format!("{}", BigEndian::read_u64(data))
    } else {
        // If data is too short, return a placeholder
        "invalid_message".to_string()
    }
}

// Custom message ID function similar to Go implementation
pub fn message_id_fn(message: &gossipsub::Message) -> MessageId {
    MessageId::from(&message.data[0..8])
}

pub struct ScriptedNode {
    node_id: NodeID,
    swarm: Swarm<MyBehavior>,
    stderr_logger: Logger,
    stdout_logger: Logger,
    connector: ShadowConnector,
    topics: HashMap<String, IdentTopic>,
    start_time: Instant,
}

use crate::connector::ShadowConnector;

impl ScriptedNode {
    pub fn new(
        node_id: NodeID,
        swarm: Swarm<MyBehavior>,
        stderr_logger: Logger,
        stdout_logger: Logger,
        connector: ShadowConnector,
        start_time: Instant,
    ) -> Self {
        info!(stdout_logger, "PeerID"; "id" => swarm.local_peer_id().to_string(), "node_id" => node_id);
        Self {
            node_id,
            swarm,
            stderr_logger,
            stdout_logger,
            connector,
            topics: HashMap::new(),
            start_time,
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

    pub fn run_action(
        &mut self,
        action: ScriptAction,
    ) -> futures::future::BoxFuture<'_, Result<(), Box<dyn std::error::Error>>> {
        Box::pin(async move {
            match action {
                ScriptAction::Connect { connect_to } => {
                    for target_node_id in connect_to {
                        match self
                            .connector
                            .connect_to(&mut self.swarm, target_node_id)
                            .await
                        {
                            Ok(_) => {
                                info!(self.stderr_logger, "Connected to node {}", target_node_id);
                            }
                            Err(e) => {
                                error!(
                                    self.stderr_logger,
                                    "Failed to connect to node {}: {}", target_node_id, e
                                );
                                return Err(e);
                            }
                        }
                    }
                    info!(
                        self.stderr_logger,
                        "Node {} connected to peers", self.node_id
                    );
                }
                ScriptAction::IfNodeIDEquals { node_id, action } => {
                    if node_id == self.node_id {
                        self.run_action(*action).await?;
                    }
                }
                ScriptAction::WaitUntil { elapsed_seconds } => {
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
                                    if let libp2p::swarm::SwarmEvent::Behaviour( MyBehaviorEvent::Gossipsub(gossipsub::Event::Message {
                                        propagation_source: peer_id,
                                        message_id: _,
                                        message,
                                    })) = event {
                                        if message.data.len() >= 8 {
                                            info!(self.stdout_logger, "Received Message";
                                                "topic" => message.topic.into_string(),
                                                "id" => calc_id(&message.data),
                                                "from" => peer_id.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                ScriptAction::Publish {
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
                            return Err(Box::new(std::io::Error::new(
                                std::io::ErrorKind::Other,
                                e.to_string(),
                            )));
                        }
                    }
                }
                ScriptAction::SubscribeToTopic { topic_id } => {
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
                            return Err(Box::new(std::io::Error::new(
                                std::io::ErrorKind::Other,
                                e.to_string(),
                            )));
                        }
                    }
                }
                ScriptAction::InitGossipSub { gossip_sub_params: _ } => {
                    // This is handled before node creation in main.rs, so we don't need to do anything here
                    info!(self.stderr_logger, "InitGossipSub action already processed");
                }
            }

            Ok(())
        })
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
    connector: ShadowConnector,
    params: ExperimentParams,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut node = ScriptedNode::new(
        node_id,
        swarm,
        stderr_logger.clone(),
        stdout_logger.clone(),
        connector,
        start_time,
    );
    for action in params.script {
        node.run_action(action).await?;
    }
    Ok(())
}

// Extract InitGossipSub parameters from script actions
pub fn extract_gossipsub_params(
    script: &[ScriptAction],
    node_id: NodeID,
) -> Option<crate::script_action::GossipSubParams> {
    for action in script {
        match action {
            ScriptAction::InitGossipSub { gossip_sub_params } => {
                return Some(gossip_sub_params.clone());
            }
            ScriptAction::IfNodeIDEquals { node_id: action_node_id, action } => {
                if *action_node_id == node_id {
                    match action.as_ref() {
                        ScriptAction::InitGossipSub { gossip_sub_params } => {
                            return Some(gossip_sub_params.clone());
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    None
}
