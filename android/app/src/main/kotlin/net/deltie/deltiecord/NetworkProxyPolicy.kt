package net.deltie.deltiecord

import android.content.Context
import android.content.Intent
import java.io.File
import org.json.JSONObject

/** Native Java sockets cannot use Flutter's SOCKS transport. */
internal object NetworkProxyPolicy {
    fun blocked(context: Context): Boolean {
        val policy = context.getSharedPreferences("send_network_privacy", Context.MODE_PRIVATE)
        // Flutter commits this decision before changing proxy configuration.
        // An explicit false is authoritative too: the detailed configuration
        // file is now encrypted and must not be parsed as native JSON.
        if (policy.contains("block_direct")) return policy.getBoolean("block_direct", true)
        // Boot receivers can run before Flutter (including after a restore).
        // This file contains routing metadata only, never proxy passwords.
        val config = File(context.filesDir, "deltiecord/network_proxy.json")
        if (!config.exists()) return false
        return try {
            if (config.length() > 8192) true
            else JSONObject(config.readText()).let {
                it.getBoolean("enabled") && !it.optBoolean("allow_direct", true)
            }
        } catch (_: Exception) { true }
    }

    fun set(context: Context, block: Boolean) {
        val wasBlocked = blocked(context)
        check(context.getSharedPreferences("send_network_privacy", Context.MODE_PRIVATE)
            .edit().putBoolean("block_direct", block).commit()) {
            "Could not save the native proxy policy."
        }
        if (block) context.stopService(Intent(context, BuiltInPushService::class.java))
        else if (wasBlocked) BuiltInPushService.resume(context)
    }
}
