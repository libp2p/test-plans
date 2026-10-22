package gossipsub.interop

import io.libp2p.etc.types.WBytes
import io.libp2p.pubsub.AbstractPubsubMessage
import io.libp2p.pubsub.MessageId
import io.libp2p.pubsub.PubsubMessage
import pubsub.pb.Rpc

/**
 * Custom PubsubMessage implementation that computes message ID
 * from the first 8 bytes of the message data (big-endian u64),
 * matching the Go and Rust implementations.
 */
class CustomIdPubsubMessage(override val protobufMessage: Rpc.Message) : AbstractPubsubMessage() {
    override val messageId: MessageId = run {
        val data = protobufMessage.data.toByteArray()
        if (data.size >= 8) {
            WBytes(data.copyOfRange(0, 8))
        } else {
            WBytes(data)
        }
    }
}

fun customIdMessageFactory(msg: Rpc.Message): PubsubMessage = CustomIdPubsubMessage(msg)
