package gossipsub.interop

import io.libp2p.core.Host
import io.libp2p.core.PeerId
import io.libp2p.core.multiformats.Multiaddr
import io.libp2p.core.pubsub.PubsubApi
import io.libp2p.core.pubsub.Topic
import io.libp2p.core.pubsub.ValidationResult
import io.libp2p.core.pubsub.Validator
import io.libp2p.core.pubsub.RESULT_VALID
import io.libp2p.etc.types.toByteBuf
import io.libp2p.pubsub.PubsubMessage
import io.libp2p.pubsub.gossip.GossipRouterEventListener
import java.net.InetAddress
import java.nio.ByteBuffer
import java.time.Duration
import java.util.Optional
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

fun formatMessageId(data: ByteArray): String {
    if (data.size >= 8) {
        val buf = ByteBuffer.wrap(data, 0, 8)
        return buf.long.toULong().toString()
    }
    return "invalid_message"
}

class MessageTracer : GossipRouterEventListener {
    override fun notifyUnseenMessage(peerId: PeerId, msg: PubsubMessage) {
        val data = msg.protobufMessage.data.toByteArray()
        JsonLogger.logStdout("Received Message",
            "id" to formatMessageId(data),
            "from" to peerId.toString(),
        )
    }

    override fun notifySeenMessage(peerId: PeerId, msg: PubsubMessage, validationResult: Optional<ValidationResult>) {
        val data = msg.protobufMessage.data.toByteArray()
        JsonLogger.logStdout("Received Message",
            "id" to formatMessageId(data),
            "from" to peerId.toString(),
        )
    }

    override fun notifyDisconnected(peerId: PeerId) {}
    override fun notifyConnected(peerId: PeerId, peerAddress: Multiaddr) {}
    override fun notifyUnseenInvalidMessage(peerId: PeerId, msg: PubsubMessage) {}
    override fun notifyUnseenValidMessage(peerId: PeerId, msg: PubsubMessage) {}
    override fun notifyMeshed(peerId: PeerId, topic: String) {}
    override fun notifyPruned(peerId: PeerId, topic: String) {}
    override fun notifyRouterMisbehavior(peerId: PeerId, count: Int) {}
}

class ScriptedNode(
    private val startTimeMillis: Long,
    private val host: Host,
    private val gossip: PubsubApi,
    private val nodeId: Int,
) {
    private val topicValidationDelays = mutableMapOf<String, Duration>()

    fun runInstruction(instruction: ScriptInstruction) {
        when (instruction) {
            is InitGossipSub -> {
                // Already handled before node creation
                JsonLogger.logStderr("InitGossipSub instruction already processed")
            }
            is Connect -> {
                for (targetNodeId in instruction.connectTo) {
                    connectTo(targetNodeId)
                }
                JsonLogger.logStderr("Node $nodeId connected to peers")
            }
            is IfNodeIDEquals -> {
                if (instruction.nodeID == nodeId) {
                    runInstruction(instruction.instruction)
                }
            }
            is WaitUntil -> {
                val targetTimeMillis = startTimeMillis + instruction.elapsedSeconds * 1000L
                val waitMillis = targetTimeMillis - System.currentTimeMillis()
                if (waitMillis > 0) {
                    JsonLogger.logStderr("Waiting ${waitMillis}ms (until elapsed: ${instruction.elapsedSeconds}s)")
                    Thread.sleep(waitMillis)
                }
            }
            is Publish -> {
                val topic = Topic(instruction.topicID)
                JsonLogger.logStderr("Publishing message ${instruction.messageID}")
                val msg = ByteArray(instruction.messageSizeBytes)
                ByteBuffer.wrap(msg, 0, 8).putLong(instruction.messageID.toLong())

                val publisher = gossip.createPublisher(null) { null }
                publisher.publish(msg.toByteBuf(), topic).get(30, TimeUnit.SECONDS)
                JsonLogger.logStderr("Published message ${instruction.messageID}")
            }
            is SubscribeToTopic -> {
                val topic = Topic(instruction.topicID)
                val delay = topicValidationDelays[instruction.topicID]

                val validator = Validator { _ ->
                    if (delay != null) {
                        CompletableFuture.supplyAsync {
                            Thread.sleep(delay.toMillis())
                            ValidationResult.Valid
                        }
                    } else {
                        RESULT_VALID
                    }
                }
                gossip.subscribe(validator, topic)
                JsonLogger.logStderr("Subscribed to topic ${instruction.topicID}")
            }
            is SetTopicValidationDelay -> {
                val delay = Duration.ofNanos((instruction.delaySeconds * 1_000_000_000).toLong())
                topicValidationDelays[instruction.topicID] = delay
            }
        }
    }

    private fun connectTo(targetNodeId: Int) {
        val hostname = "node$targetNodeId"
        val addrs = InetAddress.getAllByName(hostname)
        if (addrs.isEmpty()) {
            throw RuntimeException("Failed resolving address for $hostname")
        }
        val ip = addrs[0].hostAddress
        val peerId = nodePeerId(targetNodeId)
        val addr = Multiaddr.fromString("/ip4/$ip/tcp/9000/p2p/$peerId")
        host.network.connect(peerId, addr).get(30, TimeUnit.SECONDS)
        JsonLogger.logStderr("Connected to $hostname ($peerId)")
    }
}

fun runExperiment(
    startTimeMillis: Long,
    host: Host,
    gossip: PubsubApi,
    nodeId: Int,
    params: ExperimentParams,
) {
    val node = ScriptedNode(startTimeMillis, host, gossip, nodeId)
    for (instruction in params.script) {
        node.runInstruction(instruction)
    }
}
