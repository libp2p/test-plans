package io.libp2p.interop

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Experiment parameters loaded from params.json
 */
@Serializable
data class ExperimentParams(
    val script: List<ScriptInstruction> = emptyList()
)

/**
 * Script instruction - polymorphic based on "type" field
 */
@Serializable
sealed class ScriptInstruction

@Serializable
@SerialName("initGossipSub")
data class InitGossipSub(
    val gossipSubParams: GossipSubParams = GossipSubParams()
) : ScriptInstruction()

@Serializable
@SerialName("connect")
data class Connect(
    val connectTo: List<Int>
) : ScriptInstruction()

@Serializable
@SerialName("waitUntil")
data class WaitUntil(
    val elapsedSeconds: Int
) : ScriptInstruction()

@Serializable
@SerialName("subscribeToTopic")
data class SubscribeToTopic(
    val topicID: String,
    val partial: Boolean = false
) : ScriptInstruction()

@Serializable
@SerialName("publish")
data class Publish(
    val messageID: Long,
    val messageSizeBytes: Int,
    val topicID: String
) : ScriptInstruction()

@Serializable
@SerialName("addPartialMessage")
data class AddPartialMessage(
    val parts: Int,  // bitmap
    val topicID: String,
    val groupID: Long
) : ScriptInstruction()

@Serializable
@SerialName("publishPartial")
data class PublishPartial(
    val topicID: String,
    val groupID: Long,
    val publishToNodeIDs: List<Int>? = null
) : ScriptInstruction()

@Serializable
@SerialName("ifNodeIDEquals")
data class IfNodeIDEquals(
    val nodeID: Int,
    val instruction: ScriptInstruction
) : ScriptInstruction()

@Serializable
@SerialName("setTopicValidationDelay")
data class SetTopicValidationDelay(
    val topicID: String,
    val delaySeconds: Double
) : ScriptInstruction()

@Serializable
data class GossipSubParams(
    @SerialName("D") val d: Int? = null,
    @SerialName("Dlo") val dlo: Int? = null,
    @SerialName("Dhi") val dhi: Int? = null,
    @SerialName("Dscore") val dscore: Int? = null,
    @SerialName("Dout") val dout: Int? = null,
    @SerialName("HistoryLength") val historyLength: Int? = null,
    @SerialName("HistoryGossip") val historyGossip: Int? = null,
    @SerialName("Dlazy") val dlazy: Int? = null,
    @SerialName("GossipFactor") val gossipFactor: Double? = null,
    @SerialName("GossipRetransmission") val gossipRetransmission: Int? = null,
    @SerialName("HeartbeatInitialDelay") val heartbeatInitialDelay: Double? = null,
    @SerialName("HeartbeatInterval") val heartbeatInterval: Double? = null,
    @SerialName("FanoutTTL") val fanoutTTL: Double? = null,
    @SerialName("PrunePeers") val prunePeers: Int? = null,
    @SerialName("PruneBackoff") val pruneBackoff: Double? = null
)
