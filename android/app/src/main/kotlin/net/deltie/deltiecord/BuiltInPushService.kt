package net.deltie.deltiecord

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/** One opt-in transport socket. Matrix keys and plaintext never enter this service. */
class BuiltInPushService : Service() {
    @Volatile private var stopped = false
    @Volatile private var connection: HttpURLConnection? = null
    private var listener: Thread? = null
    @Volatile private var reconnect = CountDownLatch(1)
    private val networkCallback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connection?.disconnect()
                reconnect.countDown()
            }

            override fun onLost(network: Network) {
                connection?.disconnect()
                reconnect.countDown()
            }
        }

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                        CHANNEL,
                        "Background connection",
                        NotificationManager.IMPORTANCE_MIN,
                    )
                    .apply {
                        description = "Keeps SeND connected for incoming messages."
                        setSound(null, null)
                        enableVibration(false)
                        setShowBadge(false)
                    }
            )
        }
        val open =
            PendingIntent.getActivity(
                this,
                9003,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification =
            NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("SeND background notifications")
                .setContentText("Listening for messages. Change this in Notifications settings.")
                .setContentIntent(open)
                .setOngoing(true)
                .setSilent(true)
                .setShowWhen(false)
                .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                9003,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else startForeground(9003, notification)
        if (Build.VERSION.SDK_INT >= 24) {
            getSystemService(ConnectivityManager::class.java)
                .registerDefaultNetworkCallback(networkCallback)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (activeInstance(this) == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (listener?.isAlive != true) {
            stopped = false
            listener =
                Thread({ listen() }, "SeND-push-listener").apply {
                    isDaemon = true
                    start()
                }
        }
        return START_STICKY
    }

    private fun listen() {
        var retrySeconds = 2L
        while (!stopped) {
            val instance = activeInstance(this) ?: break
            val prefs = preferences(this)
            val topic = prefs.getString("topic", null) ?: break
            if (!BuiltInPushProtocol.validTopic(topic)) break
            try {
                val since =
                    prefs
                        .getLong("cursor", 0)
                        .coerceAtLeast(System.currentTimeMillis() / 1000 - 24 * 60 * 60)
                val current =
                    URL("$ORIGIN/$topic/json?since=$since").openConnection() as HttpURLConnection
                connection = current
                current.instanceFollowRedirects = false
                current.connectTimeout = 15_000
                current.readTimeout = 90_000
                current.setRequestProperty("Accept", "application/x-ndjson")
                current.setRequestProperty("User-Agent", "SeND Android push")
                try {
                    check(current.responseCode == 200) { "Push connection unavailable" }
                    current.inputStream.bufferedReader().use { reader ->
                        while (!stopped && activeInstance(this) == instance) {
                            val line = BuiltInPushProtocol.readLine(reader) ?: break
                            val message = runCatching { JSONObject(line) }.getOrNull() ?: continue
                            if (message.optString("topic") != topic) continue
                            when (message.optString("event")) {
                                "open" -> {
                                    setConnectionState(this, "connected")
                                    retrySeconds = 2
                                    // A subscription must exist before the gateway registers its
                                    // rate visitor.
                                    DeltiecordPushService.acceptEndpoint(
                                        this,
                                        "$ORIGIN/$topic?up=1",
                                        instance,
                                    )
                                }
                                "message" -> {
                                    val id = message.optString("id")
                                    if (!BuiltInPushProtocol.validId(id)) continue
                                    val seen = prefs.getStringSet("seen", emptySet()).orEmpty()
                                    if (id in seen) continue
                                    val payload = BuiltInPushProtocol.payload(message) ?: continue
                                    val wake =
                                        getSystemService(PowerManager::class.java)
                                            .newWakeLock(
                                                PowerManager.PARTIAL_WAKE_LOCK,
                                                "SeND:push-handoff",
                                            )
                                    wake.acquire(20_000)
                                    try {
                                        // Commit the cursor only after WorkManager has persisted
                                        // the work.
                                        DeltiecordPushService.receivePayload(
                                                this,
                                                payload,
                                                instance,
                                            )
                                            ?.result
                                            ?.get(15, TimeUnit.SECONDS)
                                        if (activeInstance(this) != instance) break
                                        val timestamp =
                                            message
                                                .optLong("time", since)
                                                .coerceAtMost(System.currentTimeMillis() / 1000)
                                        val ids = (seen.toList().takeLast(127) + id).toSet()
                                        prefs
                                            .edit()
                                            .putStringSet("seen", ids)
                                            .putLong(
                                                "cursor",
                                                maxOf(prefs.getLong("cursor", since), timestamp - 1),
                                            )
                                            .commit()
                                    } finally {
                                        if (wake.isHeld) wake.release()
                                    }
                                }
                            }
                        }
                    }
                } finally {
                    current.disconnect()
                    if (connection === current) connection = null
                }
            } catch (_: Exception) {
                // Never expose exceptions containing the private topic URL.
            }
            if (stopped || activeInstance(this) == null) break
            setConnectionState(this, "reconnecting")
            try {
                reconnect.await(
                    (retrySeconds * 1000) + SecureRandom().nextInt(1000),
                    TimeUnit.MILLISECONDS,
                )
                reconnect = CountDownLatch(1)
            } catch (_: InterruptedException) {
                break
            }
            retrySeconds = (retrySeconds * 2).coerceAtMost(300)
        }
    }

    override fun onDestroy() {
        stopped = true
        connection?.disconnect()
        listener?.interrupt()
        if (Build.VERSION.SDK_INT >= 24) {
            runCatching {
                getSystemService(ConnectivityManager::class.java)
                    .unregisterNetworkCallback(networkCallback)
            }
        }
        setConnectionState(this, "stopped")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ORIGIN = "https://push.deltie.net"
        private const val CHANNEL = "send_background_connection"

        private fun preferences(context: Context) =
            context.getSharedPreferences("send_builtin_push", Context.MODE_PRIVATE)

        fun activeInstance(context: Context): String? =
            preferences(context).getString("instance", null)

        fun isExplicitlyDisabled(context: Context) =
            preferences(context).getBoolean("disabled", false)

        fun connectionState(context: Context): String =
            preferences(context).getString("connection", "stopped")!!

        private fun setConnectionState(context: Context, state: String) {
            preferences(context).edit().putString("connection", state).apply()
        }

        fun enable(context: Context, instance: String) {
            if (activeInstance(context) != instance) {
                val random = ByteArray(32).also { SecureRandom().nextBytes(it) }
                val topic =
                    "up" + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(random)
                preferences(context)
                    .edit()
                    .clear()
                    .putString("instance", instance)
                    .putString("topic", topic)
                    .putLong("cursor", System.currentTimeMillis() / 1000)
                    .commit()
            }
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, BuiltInPushService::class.java),
                )
            } catch (error: Exception) {
                setConnectionState(context, "stopped")
                throw IllegalStateException(
                    "Android could not start background notifications. Reopen SeND and try again."
                )
            }
        }

        fun disable(context: Context, explicitly: Boolean) {
            preferences(context).edit().clear().putBoolean("disabled", explicitly).commit()
            context.stopService(Intent(context, BuiltInPushService::class.java))
        }

        fun resume(context: Context) {
            val instance = activeInstance(context) ?: return
            runCatching { enable(context, instance) }
        }
    }
}

/** No direct-boot access: session keys and the listener start after unlock. */
class BuiltInPushBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (
            intent.action == Intent.ACTION_BOOT_COMPLETED ||
                intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            BuiltInPushService.resume(context)
        }
    }
}

internal object BuiltInPushProtocol {
    fun validTopic(topic: String) = Regex("up[A-Za-z0-9_-]{43}").matches(topic)

    fun validId(id: String) = Regex("[A-Za-z0-9_-]{1,128}").matches(id)

    fun readLine(reader: BufferedReader): String? {
        val line = StringBuilder()
        while (true) {
            val char = reader.read()
            if (char == -1) return if (line.isEmpty()) null else line.toString()
            if (char == 10) return line.toString()
            if (line.length >= 256 * 1024) throw IllegalArgumentException("Push frame too large")
            line.append(char.toChar())
        }
    }

    fun payload(message: JSONObject): ByteArray? =
        runCatching {
                val body = message.optString("message")
                val bytes =
                    when (message.optString("encoding")) {
                        "base64" -> java.util.Base64.getDecoder().decode(body)
                        "" -> body.toByteArray(Charsets.UTF_8)
                        else -> return null
                    }
                bytes.takeIf { it.size <= 128 * 1024 }
            }
            .getOrNull()
}
