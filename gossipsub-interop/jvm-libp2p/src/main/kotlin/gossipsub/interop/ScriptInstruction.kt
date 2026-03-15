package gossipsub.interop

import com.fasterxml.jackson.annotation.JsonSubTypes
import com.fasterxml.jackson.annotation.JsonTypeInfo
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import com.fasterxml.jackson.module.kotlin.registerKotlinModule
import io.libp2p.pubsub.gossip.GossipParams
import io.libp2p.pubsub.gossip.defaultDHigh
import io.libp2p.pubsub.gossip.defaultDLazy
import io.libp2p.pubsub.gossip.defaultDLow
import io.libp2p.pubsub.gossip.defaultDOut
import io.libp2p.pubsub.gossip.defaultDScore
import java.io.File
import java.time.Duration

@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes(
    JsonSubTypes.Type(value = Connect::class, name = "connect"),
    JsonSubTypes.Type(value = IfNodeIDEquals::class, name = "ifNodeIDEquals"),
    JsonSubTypes.Type(value = WaitUntil::class, name = "waitUntil"),
    JsonSubTypes.Type(value = Publish::class, name = "publish"),
    JsonSubTypes.Type(value = SubscribeToTopic::class, name = "subscribeToTopic"),
    JsonSubTypes.Type(value = SetTopicValidationDelay::class, name = "setTopicValidationDelay"),
    JsonSubTypes.Type(value = InitGossipSub::class, name = "initGossipSub"),
)
sealed interface ScriptInstruction

data class Connect(val connectTo: List<Int>) : ScriptInstruction
data class IfNodeIDEquals(val nodeID: Int, val instruction: ScriptInstruction) : ScriptInstruction
data class WaitUntil(val elapsedSeconds: Int) : ScriptInstruction
data class Publish(val messageID: Int, val messageSizeBytes: Int, val topicID: String) : ScriptInstruction
data class SubscribeToTopic(val topicID: String) : ScriptInstruction
data class SetTopicValidationDelay(val topicID: String, val delaySeconds: Double) : ScriptInstruction
data class InitGossipSub(val gossipSubParams: GossipSubParamsJson) : ScriptInstruction

data class GossipSubParamsJson(
    val D: Int? = null,
    val Dlo: Int? = null,
    val Dhi: Int? = null,
    val Dscore: Int? = null,
    val Dout: Int? = null,
    val HistoryLength: Int? = null,
    val HistoryGossip: Int? = null,
    val Dlazy: Int? = null,
    val GossipFactor: Double? = null,
    val GossipRetransmission: Int? = null,
    val HeartbeatInitialDelay: Double? = null,
    val HeartbeatInterval: Double? = null,
    val FanoutTTL: Double? = null,
    val PrunePeers: Int? = null,
    val PruneBackoff: Double? = null,
    val MaxIHaveLength: Int? = null,
    val MaxIHaveMessages: Int? = null,
    val IWantFollowupTime: Double? = null,
    val IDontWantMessageThreshold: Int? = null,
)

data class ExperimentParams(val script: List<ScriptInstruction>) {
    companion object {
        fun fromJsonFile(path: String): ExperimentParams {
            val mapper = ObjectMapper().registerKotlinModule()
            return mapper.readValue(File(path))
        }
    }
}

fun GossipSubParamsJson.toGossipParams(): GossipParams {
    val d = D ?: 6
    val dLow = Dlo ?: defaultDLow(d)
    val dHigh = Dhi ?: defaultDHigh(d)
    val dScore = Dscore ?: defaultDScore(d)
    val dOut = Dout ?: defaultDOut(d, dLow)
    val dLazy = Dlazy ?: defaultDLazy(d)

    if (HeartbeatInitialDelay != null) {
        System.err.println("Warning: HeartbeatInitialDelay is not directly supported by jvm-libp2p; using as heartbeat interval initial delay")
    }

    return GossipParams(
        D = d,
        DLow = dLow,
        DHigh = dHigh,
        DScore = dScore,
        DOut = dOut,
        DLazy = dLazy,
        gossipSize = HistoryGossip ?: 3,
        gossipHistoryLength = HistoryLength ?: 5,
        gossipFactor = GossipFactor ?: 0.25,
        gossipRetransmission = GossipRetransmission ?: 3,
        heartbeatInterval = HeartbeatInterval?.let { Duration.ofNanos(it.toLong()) } ?: Duration.ofSeconds(1),
        fanoutTTL = FanoutTTL?.let { Duration.ofNanos(it.toLong()) } ?: Duration.ofSeconds(60),
        maxPeersSentInPruneMsg = PrunePeers ?: 16,
        pruneBackoff = PruneBackoff?.let { Duration.ofNanos(it.toLong()) } ?: Duration.ofMinutes(1),
        maxIHaveLength = MaxIHaveLength ?: 5000,
        maxIHaveMessages = MaxIHaveMessages ?: 10,
        iWantFollowupTime = IWantFollowupTime?.let { Duration.ofNanos(it.toLong()) } ?: Duration.ofSeconds(3),
        iDontWantMinMessageSizeThreshold = IDontWantMessageThreshold ?: 16384,
    )
}

fun extractGossipSubParams(script: List<ScriptInstruction>, nodeId: Int): GossipParams? {
    for (instruction in script) {
        when (instruction) {
            is InitGossipSub -> return instruction.gossipSubParams.toGossipParams()
            is IfNodeIDEquals -> {
                if (instruction.nodeID == nodeId && instruction.instruction is InitGossipSub) {
                    return (instruction.instruction as InitGossipSub).gossipSubParams.toGossipParams()
                }
            }
            else -> {}
        }
    }
    return null
}
