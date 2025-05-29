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

#[test]
fn test_node_priv_key() {
    let mut peer_ids = Vec::new();
    for node_id in 0..10_000 {
        let key = node_priv_key(node_id);
        let local_peer_id = libp2p::PeerId::from(key.public());
        peer_ids.push(format!(">{}:{}\n", node_id, local_peer_id));
    }
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    for key in &peer_ids {
        hasher.update(key.as_bytes());
    }
    let hash = hasher.finalize();

    let hash_str = format!("{:02x}", hash);
    let expected_hash = "11395ea896d00ca25f7f648ebb336488ee092096a5498d90d76b92eaec27867a";
    assert_eq!(
        hash_str, expected_hash,
        "Implementation did not generate peer ids correctly"
    );

    println!("SHA256 hash of all peer ids: {:02x}", hash);
}
