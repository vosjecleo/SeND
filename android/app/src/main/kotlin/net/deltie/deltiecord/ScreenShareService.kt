package net.deltie.deltiecord

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.ResultReceiver
import androidx.core.app.NotificationCompat

/** Started only after Android's screen-capture consent, before WebRTC capture. */
class ScreenShareService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val reply = intent?.getParcelableExtra<ResultReceiver>("reply")
        if (reply == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(
                    "screen_sharing", "Screen sharing", NotificationManager.IMPORTANCE_LOW
                ))
            }
            val open = PendingIntent.getActivity(this, 9004,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, "screen_sharing")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Sharing your screen")
                .setContentText("Open SeND to stop sharing.")
                .setContentIntent(open)
                .setOngoing(true)
                .setSilent(true)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(9004, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else startForeground(9004, notification)
            reply.send(0, null)
        } catch (_: Exception) {
            reply.send(1, null)
            stopSelf()
        }
        return START_NOT_STICKY
    }
}
