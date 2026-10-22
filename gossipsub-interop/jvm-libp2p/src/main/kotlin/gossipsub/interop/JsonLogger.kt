package gossipsub.interop

import com.fasterxml.jackson.databind.ObjectMapper
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

/**
 * Structured JSON logger that writes to stdout (for analysis) or stderr (for diagnostics).
 */
object JsonLogger {
    private val mapper = ObjectMapper()

    fun logStdout(msg: String, vararg fields: Pair<String, Any>) {
        val map = linkedMapOf<String, Any>(
            "time" to OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            "level" to "INFO",
            "msg" to msg,
        )
        for ((key, value) in fields) {
            map[key] = value
        }
        println(mapper.writeValueAsString(map))
        System.out.flush()
    }

    fun logStderr(msg: String) {
        System.err.println("[${OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)}] $msg")
    }
}
