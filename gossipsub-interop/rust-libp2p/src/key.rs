use crate::script_action::NodeID;
use byteorder::{ByteOrder, LittleEndian};
use libp2p::identity;

/// Generate a private key for a node ID
pub fn node_priv_key(id: NodeID) -> identity::Keypair {
    // Create a deterministic seed based on the node ID
    let mut seed = [0u8; 32];
    LittleEndian::write_i32(&mut seed[0..4], id);

    // Create a keypair from the seed
    identity::Keypair::ed25519_from_bytes(seed).expect("Failed to create keypair")
}

// This function verifies that a peer ID matches what we expect for a node ID
