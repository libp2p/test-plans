use crate::script_action::NodeID;
use dns_lookup::lookup_host;
use libp2p::identity::Keypair;
use libp2p::swarm::{DialError, NetworkBehaviour};
use libp2p::{Multiaddr, PeerId, Swarm};
use std::str::FromStr;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConnectorError {
    #[error("DNS lookup error: {0:?}")]
    DnsLookup(#[from] std::io::Error),
    #[error("Address parse error: {0}")]
    AddrParse(#[from] libp2p::multiaddr::Error),
    #[error("Failed to resolve address: no records returned for `{0}`")]
    FailedToResolveAddress(String),
    #[error("Connection error: {0}")]
    Connect(#[from] DialError),
}

pub async fn connect_to<B: NetworkBehaviour + Send>(
    swarm: &mut Swarm<B>,
    target_node_id: NodeID,
) -> Result<(), ConnectorError> {
    // Resolve IP addresses of the target node
    let hostname = format!("node{target_node_id}");
    let mut ips = lookup_host(&hostname)?;

    // Try to connect using the first IP address
    let ip = ips
        .pop()
        .ok_or(ConnectorError::FailedToResolveAddress(hostname))?;
    let addr = format!("/ip4/{ip}/tcp/9000");
    let multi_addr = Multiaddr::from_str(&addr)?;

    // Get the PeerId from the target node's ID
    let keypair: Keypair = target_node_id.into();
    let peer_id = PeerId::from(keypair.public());

    // Combine the address with the peer ID
    let addr_with_peer = multi_addr.with(libp2p::multiaddr::Protocol::P2p(peer_id));

    // Attempt to dial the peer
    swarm.dial(addr_with_peer.clone())?;
    Ok(())
}
