package gossipsub.interop

import io.libp2p.core.PeerId
import io.libp2p.core.crypto.PrivKey
import io.libp2p.crypto.keys.unmarshalEd25519PrivateKey

/**
 * Deterministically generate an ED25519 private key from a node ID.
 * The node ID is written as a little-endian 32-bit integer into a 32-byte seed.
 */
fun nodePrivKey(nodeId: Int): PrivKey {
    val seed = ByteArray(32)
    seed[0] = (nodeId and 0xFF).toByte()
    seed[1] = ((nodeId shr 8) and 0xFF).toByte()
    seed[2] = ((nodeId shr 16) and 0xFF).toByte()
    seed[3] = ((nodeId shr 24) and 0xFF).toByte()
    return unmarshalEd25519PrivateKey(seed)
}

fun nodePeerId(nodeId: Int): PeerId {
    return PeerId.fromPubKey(nodePrivKey(nodeId).publicKey())
}
