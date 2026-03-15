package gossipsub.interop

import io.libp2p.core.PeerId
import org.junit.jupiter.api.Test
import java.security.MessageDigest
import kotlin.test.assertEquals

class NodeKeyTest {

    @Test
    fun `test peer ID generation matches Go and Rust implementations`() {
        val peerIds = mutableListOf<String>()
        for (nodeId in 0 until 10_000) {
            val key = nodePrivKey(nodeId)
            val peerId = PeerId.fromPubKey(key.publicKey())
            peerIds.add(">$nodeId:${peerId.toBase58()}\n")
        }

        val digest = MessageDigest.getInstance("SHA-256")
        for (peerIdStr in peerIds) {
            digest.update(peerIdStr.toByteArray())
        }
        val hash = digest.digest()
        val hashStr = hash.joinToString("") { "%02x".format(it) }

        val expectedHash = "11395ea896d00ca25f7f648ebb336488ee092096a5498d90d76b92eaec27867a"
        assertEquals(expectedHash, hashStr, "Implementation did not generate peer ids correctly")
        println("SHA256 hash of all peer ids: $hashStr")
    }
}
