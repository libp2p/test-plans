package io.libp2p.interop

import io.libp2p.pubsub.partial.PartialMessage
import io.libp2p.pubsub.partial.PartialPublishAction
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Partial message implementation for interop testing.
 *
 * Message format:
 * - First byte: bitmap of which parts are included
 * - Then each present part (1024 bytes each)
 * - Last 8 bytes: groupID (big endian)
 */
class InteropPartialMessage(
    private val groupIdBytes: ByteArray
) : PartialMessage {

    companion object {
        const val PART_LEN = 1024
        const val NUM_PARTS = 8
    }

    // 8 parts, each 1024 bytes or null if not present
    private val parts = arrayOfNulls<ByteArray>(NUM_PARTS)

    override fun groupId(): ByteArray = groupIdBytes.copyOf()

    override fun partsMetadata(): ByteArray {
        var bitmap = 0
        for (i in 0 until NUM_PARTS) {
            if (parts[i] != null) {
                bitmap = bitmap or (1 shl i)
            }
        }
        return byteArrayOf(bitmap.toByte())
    }

    override fun partialMessageBytes(requestedMetadata: ByteArray?): PartialPublishAction {
        val theirBitmap = requestedMetadata?.getOrNull(0)?.toInt()?.and(0xFF) ?: 0

        val partsToSend = mutableListOf<ByteArray>()
        var ourBitmap = 0

        for (i in 0 until NUM_PARTS) {
            val part = parts[i] ?: continue
            // Only send parts they don't have
            if ((theirBitmap and (1 shl i)) == 0) {
                ourBitmap = ourBitmap or (1 shl i)
                partsToSend.add(part)
            }
        }

        if (ourBitmap == 0) {
            // Check if we need more parts from them
            val myBitmap = partsMetadata()[0].toInt() and 0xFF
            val needMore = (theirBitmap and myBitmap.inv()) != 0
            return PartialPublishAction(needMore, null, partsMetadata())
        }

        // Format: [bitmap][parts...][groupId]
        val totalSize = 1 + (partsToSend.size * PART_LEN) + groupIdBytes.size
        val buffer = ByteBuffer.allocate(totalSize)
        buffer.put(ourBitmap.toByte())
        partsToSend.forEach { buffer.put(it) }
        buffer.put(groupIdBytes)

        val myBitmap = partsMetadata()[0].toInt() and 0xFF
        val needMore = (theirBitmap and myBitmap.inv()) != 0

        return PartialPublishAction(needMore, buffer.array(), partsMetadata())
    }

    /**
     * Fill parts based on bitmap for testing.
     * Each part contains sequential uint64s starting from groupID.
     */
    fun fillParts(bitmap: Int) {
        val startValue = ByteBuffer.wrap(groupIdBytes).order(ByteOrder.BIG_ENDIAN).getLong()

        for (i in 0 until NUM_PARTS) {
            if ((bitmap and (1 shl i)) == 0) continue

            val part = ByteArray(PART_LEN)
            val partBuffer = ByteBuffer.wrap(part).order(ByteOrder.BIG_ENDIAN)
            var counter = startValue + (i * PART_LEN / 8)

            repeat(PART_LEN / 8) {
                partBuffer.putLong(counter++)
            }
            parts[i] = part
        }
    }

    /**
     * Extend this partial message with received data.
     * Returns true if we now have all parts.
     */
    fun extend(data: ByteArray): Boolean {
        if (data.size < 1 + groupIdBytes.size) return false

        val partBitmap = data[0].toInt() and 0xFF
        val groupIdStart = data.size - groupIdBytes.size
        val receivedGroupId = data.sliceArray(groupIdStart until data.size)

        if (!receivedGroupId.contentEquals(groupIdBytes)) return false

        var offset = 1
        for (i in 0 until NUM_PARTS) {
            if (offset >= groupIdStart) break
            if ((partBitmap and (1 shl i)) == 0) continue

            if (parts[i] == null) {
                parts[i] = data.sliceArray(offset until (offset + PART_LEN))
            }
            offset += PART_LEN
        }

        return isComplete()
    }

    fun isComplete(): Boolean = parts.all { it != null }

    fun hasPart(index: Int): Boolean = parts.getOrNull(index) != null
}

/**
 * Merge two metadata bitmaps using bitwise OR.
 */
fun mergeMetadata(left: ByteArray, right: ByteArray): ByteArray {
    val maxLen = maxOf(left.size, right.size)
    val result = ByteArray(maxLen)
    for (i in 0 until maxLen) {
        val l = if (i < left.size) left[i].toInt() and 0xFF else 0
        val r = if (i < right.size) right[i].toInt() and 0xFF else 0
        result[i] = (l or r).toByte()
    }
    return result
}
