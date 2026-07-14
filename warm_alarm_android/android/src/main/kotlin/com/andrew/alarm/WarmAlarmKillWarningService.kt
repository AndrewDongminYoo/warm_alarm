package com.andrew.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * A no-op started service whose only purpose is to catch [onTaskRemoved] — the
 * callback Android delivers when the user swipes the app off the recents list.
 *
 * Unlike [WarmAlarmForegroundService], which runs only while an alarm is
 * ringing, this service is started as soon as an alarm is *scheduled*. That is
 * what makes the kill warning cover its dominant failure mode: an app swiped
 * away hours before its alarm is due, which on aggressive OEMs never wakes to
 * ring. The manifest declares `android:stopWithTask="false"` so the OS delivers
 * [onTaskRemoved] instead of silently killing the service with the task.
 *
 * The channel and notification ids intentionally match
 * [WarmAlarmForegroundService]'s kill-warning constants, so when both services
 * observe the same swipe (an alarm ringing at kill time) the two posts collapse
 * into one notification rather than stacking.
 */
class WarmAlarmKillWarningService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    KILL_WARNING_CHANNEL_ID,
                    "Alarm Kill Warning",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notifies when the app is killed while an alarm is scheduled"
                }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int = START_STICKY

    override fun onTaskRemoved(rootIntent: Intent?) {
        val now = System.currentTimeMillis()
        val hasFutureAlarm = WarmAlarmStore.loadAll(this).values.any { it.scheduledAtMillis > now }
        if (hasFutureAlarm || WarmAlarmForegroundService.isRinging) {
            val prefs = getSharedPreferences(WarmAlarmPlugin.KILL_WARNING_PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("title", null)
            val body = prefs.getString("body", null)
            if (title != null && body != null) {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val notification =
                    NotificationCompat
                        .Builder(this, KILL_WARNING_CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.ic_dialog_alert)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true)
                        .build()
                nm.notify(KILL_WARNING_NOTIF_ID, notification)
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    companion object {
        // Shared with WarmAlarmForegroundService (single source of truth) so the two
        // services' notifications dedupe on the same channel and id.
        private const val KILL_WARNING_CHANNEL_ID = WarmAlarmForegroundService.KILL_WARNING_CHANNEL_ID
        private const val KILL_WARNING_NOTIF_ID = WarmAlarmForegroundService.KILL_WARNING_NOTIF_ID

        /** Caller must be in a foreground context — Android 8+ forbids
         * `startService` from the background (e.g. a background isolate). */
        fun start(context: Context) {
            context.startService(Intent(context, WarmAlarmKillWarningService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WarmAlarmKillWarningService::class.java))
        }
    }
}
