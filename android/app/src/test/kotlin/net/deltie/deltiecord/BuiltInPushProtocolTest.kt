package net.deltie.deltiecord

import java.io.StringReader
import java.util.Base64
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class BuiltInPushProtocolTest {
    @Test
    fun topicFitsNtfyLimitAndContainsNoAccountIdentifier() {
        val topic =
            "up" +
                Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(ByteArray(32) { it.toByte() })
        assertTrue(BuiltInPushProtocol.validTopic(topic))
        assertTrue(topic.length <= 64)
        assertFalse(BuiltInPushProtocol.validTopic("up../secrets"))
        assertFalse(BuiltInPushProtocol.validTopic("up@alice:example.org"))
    }

    @Test
    fun boundedStreamHandlesFramesAndEof() {
        val reader = StringReader("first\nsecond\nlast").buffered()
        assertEquals("first", BuiltInPushProtocol.readLine(reader))
        assertEquals("second", BuiltInPushProtocol.readLine(reader))
        assertEquals("last", BuiltInPushProtocol.readLine(reader))
        assertNull(BuiltInPushProtocol.readLine(reader))
        assertThrows(IllegalArgumentException::class.java) {
            BuiltInPushProtocol.readLine(StringReader("x".repeat(256 * 1024 + 1)).buffered())
        }
    }

    @Test
    fun utf8AndBase64DecodeToSameMetadata() {
        val payload = "{\"notification\":{\"room_id\":\"!test:example.org\"}}"
        assertArrayEquals(
            payload.toByteArray(),
            BuiltInPushProtocol.payload(JSONObject().put("message", payload)),
        )
        assertArrayEquals(
            payload.toByteArray(),
            BuiltInPushProtocol.payload(
                JSONObject()
                    .put("message", Base64.getEncoder().encodeToString(payload.toByteArray()))
                    .put("encoding", "base64")
            ),
        )
        assertNull(
            BuiltInPushProtocol.payload(
                JSONObject().put("message", "invalid$").put("encoding", "base64")
            )
        )
        assertNull(
            BuiltInPushProtocol.payload(JSONObject().put("message", "x").put("encoding", "unknown"))
        )
        assertNull(
            BuiltInPushProtocol.payload(JSONObject().put("message", "x".repeat(128 * 1024 + 1)))
        )
    }
}
