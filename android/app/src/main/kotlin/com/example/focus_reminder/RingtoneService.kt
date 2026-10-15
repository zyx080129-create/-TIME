package com.example.focus_reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RingtoneService : Service() {
    private var ringtone: Ringtone? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getIntExtra(EXTRA_ID, 0) ?: 0
        val preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
        val uri = preferences.getString(KEY_URI, null)?.let(Uri::parse)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ringtone = RingtoneManager.getRingtone(this, uri)?.also {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) it.isLooping = true
            it.play()
        }
        startForeground(NOTIFICATION_ID, buildNotification(id))
        return START_STICKY
    }

    private fun buildNotification(id: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "正在响铃", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val stopIntent = Intent(this, AlarmReceiver::class.java).setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, id, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(com.example.focus_reminder.R.mipmap.ic_launcher)
            .setContentTitle("强提醒正在响铃")
            .setContentText("请点击“停止响铃”关闭提醒")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .addAction(0, "停止响铃", stopPendingIntent)
            .build()
    }

    override fun onDestroy() {
        ringtone?.stop()
        ringtone = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_STOP = "com.example.focus_reminder.STOP_RINGTONE"
        const val EXTRA_ID = "notification_id"
        const val PREFERENCES = "notification_preferences"
        const val KEY_URI = "ringtone_uri"
        private const val CHANNEL_ID = "ringing_alarm"
        private const val NOTIFICATION_ID = 2147483000
    }
}
