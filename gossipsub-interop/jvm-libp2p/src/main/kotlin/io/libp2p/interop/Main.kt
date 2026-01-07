package io.libp2p.interop

import io.libp2p.core.Host
import io.libp2p.core.PeerId
import io.libp2p.core.crypto.PrivKey
import io.libp2p.core.dsl.host
import io.libp2p.core.multiformats.Multiaddr
import io.libp2p.core.mux.StreamMuxerProtocol
import io.libp2p.core.pubsub.MessageApi
import io.libp2p.core.pubsub.PubsubPublisherApi
import io.libp2p.core.pubsub.Subscriber
import io.libp2p.core.pubsub.Topic
import io.libp2p.crypto.keys.Ed25519PrivateKey
import io.libp2p.pubsub.gossip.Gossip
import io.libp2p.pubsub.gossip.GossipParams
import io.libp2p.pubsub.gossip.builders.GossipParamsBuilder
import io.libp2p.pubsub.gossip.builders.GossipRouterBuilder
import io.libp2p.pubsub.partial.BitwiseOrMerger
import io.libp2p.pubsub.partial.PartialMessageExtension
import pubsub.pb.Rpc
import io.libp2p.security.noise.NoiseXXSecureChannel
import io.libp2p.transport.tcp.TcpTransport
import io.netty.buffer.ByteBufUtil
import io.netty.buffer.Unpooled
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.modules.SerializersModule
import kotlinx.serialization.modules.polymorphic
import kotlinx.serialization.modules.subclass
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import java.io.File
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import kotlin.system.exitProcess

// Global state
var nodeId: Int = 0
lateinit var peerId: PeerId
lateinit var privKey: PrivKey
lateinit var gossip: Gossip
lateinit var libp2pHost: Host
lateinit var publisher: PubsubPublisherApi
val partialMessages = ConcurrentHashMap<Long, InteropPartialMessage>()
val startTime = System.currentTimeMillis()
val subscribedTopics = mutableSetOf<String>()

val json = Json {
    ignoreUnknownKeys = true
    isLenient = true
    classDiscriminator = "type"
    serializersModule = SerializersModule {
        polymorphic(ScriptInstruction::class) {
            subclass(InitGossipSub::class)
            subclass(Connect::class)
            subclass(WaitUntil::class)
            subclass(SubscribeToTopic::class)
            subclass(Publish::class)
            subclass(AddPartialMessage::class)
            subclass(PublishPartial::class)
            subclass(IfNodeIDEquals::class)
            subclass(SetTopicValidationDelay::class)
        }
    }
}

fun main(args: Array<String>) {
    // Parse --params argument
    val paramsIndex = args.indexOf("--params")
    if (paramsIndex == -1 || paramsIndex + 1 >= args.size) {
        System.err.println("Usage: gossipsub-bin --params <params.json>")
        exitProcess(1)
    }
    val paramsFile = File(args[paramsIndex + 1])

    // Get node ID from hostname (format: "node0", "node1", etc.)
    val hostname = InetAddress.getLocalHost().hostName
    nodeId = hostname.removePrefix("node").toIntOrNull() ?: 0

    // Generate deterministic key from node ID (little-endian encoded)
    val seed = ByteArray(32)
    ByteBuffer.wrap(seed).order(ByteOrder.LITTLE_ENDIAN).putInt(nodeId)
    val keyParams = Ed25519PrivateKeyParameters(seed, 0)
    privKey = Ed25519PrivateKey(keyParams)
    peerId = PeerId.fromPubKey(privKey.publicKey())

    // Log PeerID
    logJson("PeerID", mapOf("id" to peerId.toBase58(), "node_id" to nodeId))

    // Parse params
    val paramsText = paramsFile.readText()
    val params = json.decodeFromString<ExperimentParams>(paramsText)

    // Execute script
    for (instruction in params.script) {
        executeInstruction(instruction, params)
    }

    // Keep running for a bit to handle any remaining messages
    Thread.sleep(1000)

    // Clean shutdown
    System.err.println("Script completed, shutting down")
    libp2pHost.stop().get()
    exitProcess(0)
}

fun executeInstruction(instruction: ScriptInstruction, params: ExperimentParams) {
    when (instruction) {
        is InitGossipSub -> initGossipSub(instruction.gossipSubParams)
        is Connect -> connect(instruction.connectTo)
        is WaitUntil -> waitUntil(instruction.elapsedSeconds)
        is SubscribeToTopic -> subscribeToTopic(instruction.topicID, instruction.partial)
        is Publish -> publish(instruction.messageID, instruction.messageSizeBytes, instruction.topicID)
        is AddPartialMessage -> addPartialMessage(instruction.parts, instruction.topicID, instruction.groupID)
        is PublishPartial -> publishPartial(instruction.topicID, instruction.groupID, instruction.publishToNodeIDs)
        is IfNodeIDEquals -> {
            if (instruction.nodeID == nodeId) {
                executeInstruction(instruction.instruction, params)
            }
        }
        is SetTopicValidationDelay -> {
            // Not implemented - just ignore
        }
    }
}

fun initGossipSub(gsParams: GossipSubParams) {
    val paramsBuilder = GossipParamsBuilder()

    gsParams.d?.let { paramsBuilder.D(it) }
    gsParams.dlo?.let { paramsBuilder.DLow(it) }
    gsParams.dhi?.let { paramsBuilder.DHigh(it) }
    gsParams.dscore?.let { paramsBuilder.DScore(it) }
    gsParams.dout?.let { paramsBuilder.DOut(it) }
    gsParams.dlazy?.let { paramsBuilder.DLazy(it) }

    // Convert nanoseconds to Duration
    gsParams.heartbeatInterval?.let {
        paramsBuilder.heartbeatInterval(Duration.ofNanos(it.toLong()))
    }

    val gossipParams = paramsBuilder.build()

    // Build router with partial message support
    val routerBuilder = GossipRouterBuilder()
    routerBuilder.params = gossipParams
    routerBuilder.partialMessageExtension = PartialMessageExtension(
        metadataMerger = BitwiseOrMerger,
        onIncomingRpc = { peerId, rpc ->
            handlePartialRpc(peerId, rpc)
        }
    )
    val router = routerBuilder.build()

    gossip = Gossip(router)

    libp2pHost = host {
        identity {
            factory = { privKey }
        }
        transports {
            add(::TcpTransport)
        }
        secureChannels {
            add(::NoiseXXSecureChannel)
        }
        muxers {
            +StreamMuxerProtocol.Mplex
        }
        network {
            listen("/ip4/0.0.0.0/tcp/9000")
        }
        protocols {
            +gossip
        }
    }

    libp2pHost.start().get()

    // Create publisher for this node
    publisher = gossip.createPublisher(privKey)

    System.err.println("Node $nodeId started with PeerId: ${peerId.toBase58()}")
}

fun connect(nodeIds: List<Int>) {
    for (targetNodeId in nodeIds) {
        // Generate deterministic peer ID for target node
        val targetSeed = ByteArray(32)
        ByteBuffer.wrap(targetSeed).order(ByteOrder.LITTLE_ENDIAN).putInt(targetNodeId)
        val targetKeyParams = Ed25519PrivateKeyParameters(targetSeed, 0)
        val targetPrivKey = Ed25519PrivateKey(targetKeyParams)
        val targetPeerId = PeerId.fromPubKey(targetPrivKey.publicKey())

        val targetAddr = Multiaddr("/ip4/11.0.0.${targetNodeId + 1}/tcp/9000/p2p/${targetPeerId.toBase58()}")
        try {
            libp2pHost.network.connect(targetPeerId, targetAddr).get()
            System.err.println("Connected to node $targetNodeId (${targetPeerId.toBase58()})")
        } catch (e: Exception) {
            System.err.println("Failed to connect to node $targetNodeId: ${e.message}")
        }
    }
}

fun waitUntil(elapsedSeconds: Int) {
    val targetTime = startTime + (elapsedSeconds * 1000L)
    val sleepTime = targetTime - System.currentTimeMillis()
    if (sleepTime > 0) {
        Thread.sleep(sleepTime)
    }
}

fun subscribeToTopic(topicId: String, partial: Boolean) {
    val topic = Topic(topicId)

    val subscriber = Subscriber { pubsubMessage: MessageApi ->
        handleMessage(pubsubMessage, topicId)
    }

    // If partial, ONLY send subscription with requestsPartial flag
    // Don't send regular subscribe first since gossip.subscribe will do that
    if (partial) {
        // Add the message handler
        gossip.subscribe(subscriber, topic)
        // Then immediately send partial subscription (this will queue a second sub with partial flag)
        gossip.subscribePartial(topic)
        System.err.println("Subscribed to topic: $topicId with partial message support (sent both regular and partial subscription)")
    } else {
        gossip.subscribe(subscriber, topic)
        System.err.println("Subscribed to topic: $topicId")
    }

    subscribedTopics.add(topicId)
}

fun handleMessage(message: MessageApi, topicId: String) {
    val data = ByteBufUtil.getBytes(message.data)

    System.err.println("Received message on topic $topicId, size=${data.size}")

    // Check if this is a partial message (has extension data)
    // For now, treat all messages as regular or check size
    if (data.size >= 8) {
        // Extract message ID from first 8 bytes (big endian)
        val messageId = ByteBuffer.wrap(data, 0, 8).order(ByteOrder.BIG_ENDIAN).getLong()

        // Get sender peer ID from bytes
        val fromPeerId = message.from?.let { PeerId(it) }

        logJson("Received Message", mapOf(
            "id" to messageId.toString(),
            "topic" to topicId,
            "from" to (fromPeerId?.toBase58() ?: "unknown")
        ))

        // Check if this completes a partial message
        if (data.size > 8) {
            val groupIdStart = data.size - 8
            val groupIdBytes = data.sliceArray(groupIdStart until data.size)
            val groupId = ByteBuffer.wrap(groupIdBytes).order(ByteOrder.BIG_ENDIAN).getLong()

            val partialMsg = partialMessages.computeIfAbsent(groupId) {
                InteropPartialMessage(groupIdBytes)
            }

            if (partialMsg.extend(data)) {
                logJson("All parts received", mapOf(
                    "groupId" to groupId.toString(),
                    "topic" to topicId
                ))
            }
        }
    }
}

fun publish(messageId: Long, messageSizeBytes: Int, topicId: String) {
    val data = ByteArray(messageSizeBytes)
    ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN).putLong(messageId)

    val topic = Topic(topicId)
    publisher.publish(Unpooled.wrappedBuffer(data), topic)

    System.err.println("Published message $messageId to topic $topicId")
}

fun addPartialMessage(parts: Int, topicId: String, groupId: Long) {
    val groupIdBytes = ByteArray(8)
    ByteBuffer.wrap(groupIdBytes).order(ByteOrder.BIG_ENDIAN).putLong(groupId)

    val partialMsg = partialMessages.computeIfAbsent(groupId) {
        InteropPartialMessage(groupIdBytes)
    }
    partialMsg.fillParts(parts)

    System.err.println("Added partial message groupId=$groupId parts=$parts to topic $topicId")
}

fun publishPartial(topicId: String, groupId: Long, targetNodeIds: List<Int>?) {
    val partialMsg = partialMessages[groupId]
    if (partialMsg == null) {
        System.err.println("No partial message found for groupId=$groupId")
        return
    }

    val topic = Topic(topicId)

    // Publish to mesh peers (or specific nodes if specified)
    gossip.publishPartial(partialMsg, topic)

    System.err.println("Published partial message groupId=$groupId to topic $topicId")
}

fun handlePartialRpc(peerId: PeerId, rpc: Rpc.PartialMessagesExtension) {
    if (!rpc.hasTopicID()) return
    if (!rpc.hasGroupID()) return

    val topicId = rpc.topicID.toStringUtf8()
    val groupIdBytes = rpc.groupID.toByteArray()
    val groupId = ByteBuffer.wrap(groupIdBytes).order(ByteOrder.BIG_ENDIAN).getLong()

    // Get or create the partial message for this group
    val partialMsg = partialMessages.computeIfAbsent(groupId) {
        InteropPartialMessage(groupIdBytes)
    }

    // Extend with received data
    val wasComplete = partialMsg.isComplete()
    if (rpc.hasPartialMessage() && rpc.partialMessage.size() > 0) {
        val data = rpc.partialMessage.toByteArray()
        val extendResult = partialMsg.extend(data)
        if (extendResult || (!wasComplete && partialMsg.isComplete())) {
            logJson("All parts received", mapOf(
                "groupId" to groupId.toString(),
                "topic" to topicId
            ))
        }
    }

    // If we extended our set, republish to mesh peers
    val myMetadata = partialMsg.partsMetadata()[0].toInt() and 0xFF
    val theirMetadata = if (rpc.hasPartsMetadata()) {
        val pm = rpc.partsMetadata
        if (pm.size() > 0) pm.byteAt(0).toInt() and 0xFF else 0
    } else 0

    // Republish if we have parts they don't have
    if (myMetadata != theirMetadata) {
        val topic = Topic(topicId)
        gossip.publishPartial(partialMsg, topic)
    }
}

fun logJson(msg: String, extra: Map<String, Any> = emptyMap()) {
    val timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
    val logEntry = buildString {
        append("{")
        append("\"time\":\"$timestamp\",")
        append("\"level\":\"INFO\",")
        append("\"msg\":\"$msg\",")
        append("\"service\":\"gossipsub\"")
        extra.forEach { (k, v) ->
            append(",\"$k\":")
            when (v) {
                is String -> append("\"$v\"")
                is Number -> append(v)
                else -> append("\"$v\"")
            }
        }
        append("}")
    }
    println(logEntry)
}
