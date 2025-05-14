use crate::key::node_priv_key;
use crate::script_action::NodeID;
use dns_lookup::lookup_host;
use libp2p::swarm::NetworkBehaviour;
use libp2p::{Multiaddr, PeerId, Swarm};
use std::error::Error;
use std::fmt;
use std::str::FromStr;

#[derive(Debug)]
pub enum ConnectorError {
    DnsLookupError(dns_lookup::LookupError),
    AddrParseError(std::net::AddrParseError),
    ConnectError(String),
}

impl fmt::Display for ConnectorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectorError::DnsLookupError(e) => write!(f, "DNS lookup error: {:?}", e),
            ConnectorError::AddrParseError(e) => write!(f, "Address parse error: {}", e),
            ConnectorError::ConnectError(e) => write!(f, "Connection error: {}", e),
        }
    }
}

impl Error for ConnectorError {}

impl From<dns_lookup::LookupError> for ConnectorError {
    fn from(err: dns_lookup::LookupError) -> Self {
        ConnectorError::DnsLookupError(err)
    }
}

impl From<std::net::AddrParseError> for ConnectorError {
    fn from(err: std::net::AddrParseError) -> Self {
        ConnectorError::AddrParseError(err)
    }
}

/// Trait for host connectors
pub trait HostConnector<B: NetworkBehaviour>: Send + Sync {
    fn connect_to<'a>(
        &'a self,
        swarm: &'a mut Swarm<B>,
        target_node_id: NodeID,
    ) -> futures::future::BoxFuture<'a, Result<(), Box<dyn Error>>>;
}

/// Shadow-specific connector implementation
pub struct ShadowConnector;

impl<B: NetworkBehaviour + Send> HostConnector<B> for ShadowConnector {
    fn connect_to<'a>(
        &'a self,
        swarm: &'a mut Swarm<B>,
        target_node_id: NodeID,
    ) -> futures::future::BoxFuture<'a, Result<(), Box<dyn Error>>> {
        Box::pin(async move {
            // Resolve IP addresses of the target node
            let hostname = format!("node{}", target_node_id);
            let ips = match lookup_host(&hostname) {
                Ok(ips) => ips,
                Err(e) => {
                    return Err(Box::new(ConnectorError::ConnectError(format!(
                        "DNS lookup error: {}",
                        e
                    ))) as Box<dyn Error>)
                }
            };

            if ips.is_empty() {
                return Err(Box::new(ConnectorError::ConnectError(format!(
                    "Failed to resolve address for {}",
                    hostname
                ))) as Box<dyn Error>);
            }

            // Get the PeerId from the target node's ID
            let priv_key = node_priv_key(target_node_id);
            let peer_id = PeerId::from(priv_key.public());

            // Try to connect using the first IP address
            let ip = ips[0];
            let addr = format!("/ip4/{}/tcp/9000", ip);
            let multi_addr = match Multiaddr::from_str(&addr) {
                Ok(addr) => addr,
                Err(e) => {
                    return Err(Box::new(ConnectorError::ConnectError(format!(
                        "Address parse error: {}",
                        e
                    ))) as Box<dyn Error>)
                }
            };

            // Combine the address with the peer ID
            let addr_with_peer = multi_addr.with(libp2p::multiaddr::Protocol::P2p(peer_id.into()));

            // Attempt to dial the peer
            if let Err(e) = swarm.dial(addr_with_peer.clone()) {
                return Err(Box::new(ConnectorError::ConnectError(e.to_string())) as Box<dyn Error>);
            }

            Ok(())
        })
    }
}
