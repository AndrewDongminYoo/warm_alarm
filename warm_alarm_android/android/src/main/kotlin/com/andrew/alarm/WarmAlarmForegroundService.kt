package com.andrew.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File

class WarmAlarmForegroundService : Service() {
    companion object {
        const val ACTION_STOP = "com.andrew.alarm.ACTION_STOP"
        const val ACTION_SNOOZE = "com.andrew.alarm.ACTION_SNOOZE"
        const val EXTRA_ALARM_ID = WarmAlarmReceiver.EXTRA_ALARM_ID
        const val CHANNEL_ID = "warm_alarm_channel"
        private const val NOTIF_ID = 2001
        private const val WAKE_CHECK_PENDING_OFFSET = 30_000
    }

    private var mediaPlayer: MediaPlayer? = null
    private var currentSchedule: WarmAlarmScheduleWire? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val action = intent?.action
        val alarmId = intent?.getLongExtra(EXTRA_ALARM_ID, -1L) ?: -1L

        when (action) {
            ACTION_STOP -> handleStop(alarmId)
            ACTION_SNOOZE -> handleSnooze(alarmId)
            else -> handleFire(alarmId)
        }
        return START_NOT_STICKY
    }

    private fun handleFire(alarmId: Long) {
        if (alarmId == -1L) {
            stopSelf()
            return
        }
        val schedule = WarmAlarmStore.load(this, alarmId)
        currentSchedule = schedule
        startForeground(NOTIF_ID, buildNotification(alarmId, schedule))
        startAudio(alarmId, schedule)
    }

    private fun handleStop(alarmId: Long) {
        stopAudio()
        WarmAlarmPlugin.emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.STOPPED,
                occurredAtMillis = System.currentTimeMillis(),
            ),
        )
        val schedule = currentSchedule ?: WarmAlarmStore.load(this, alarmId)
        val wakeCheckDelay = schedule?.wakeCheck?.checkDelayMillis
        val maxRetriggers = (schedule?.wakeCheck?.maxRetriggers ?: 1L).toInt()
        val retriggerCount = WarmAlarmStore.getRetriggerCount(this, alarmId)
        if (wakeCheckDelay != null && retriggerCount < maxRetriggers) {
            scheduleWakeCheck(alarmId, System.currentTimeMillis() + wakeCheckDelay)
        } else {
            WarmAlarmStore.remove(this, alarmId)
        }
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    private fun scheduleWakeCheck(
        alarmId: Long,
        checkAtMillis: Long,
    ) {
        val intent =
            Intent(this, WarmAlarmReceiver::class.java).apply {
                action = WarmAlarmReceiver.ACTION_WAKE_CHECK_FIRE
                putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
            }
        val pending =
            PendingIntent.getBroadcast(
                this,
                (alarmId + WAKE_CHECK_PENDING_OFFSET).toInt(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        am.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, checkAtMillis, pending)
    }

    private fun handleSnooze(alarmId: Long) {
        stopAudio()
        val schedule = currentSchedule ?: WarmAlarmStore.load(this, alarmId)
        val snoozeDurationMillis = schedule?.snooze?.durationMillis ?: (5L * 60 * 1000)
        val fireAt = System.currentTimeMillis() + snoozeDurationMillis

        if (schedule != null) {
            WarmAlarmStore.reschedule(this, alarmId, fireAt)
        }
        WarmAlarmPlugin.rescheduleAlarm(this, alarmId, fireAt)

        WarmAlarmPlugin.emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.SNOOZED,
                occurredAtMillis = System.currentTimeMillis(),
                snoozeDurationMillis = snoozeDurationMillis,
            ),
        )
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    private fun startAudio(
        alarmId: Long,
        schedule: WarmAlarmScheduleWire?,
    ) {
        val audio = schedule?.audio
        val player = MediaPlayer()
        try {
            when {
                !audio?.filePath.isNullOrBlank() -> {
                    player.setDataSource(this, Uri.fromFile(File(audio!!.filePath!!)))
                }

                !audio?.assetPath.isNullOrBlank() -> {
                    val fd = assets.openFd("flutter_assets/${audio!!.assetPath}")
                    player.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                    fd.close()
                }

                else -> {
                    val uri =
                        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    player.setDataSource(this, uri)
                }
            }
            player.setAudioAttributes(
                AudioAttributes
                    .Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            player.isLooping = audio?.loop ?: true
            player.prepare()
            player.start()
            mediaPlayer = player
        } catch (e: Exception) {
            player.release()
            if (alarmId != -1L) {
                WarmAlarmPlugin.emitEventFromBackground(
                    WarmAlarmEventWire(
                        alarmId = alarmId,
                        type = WarmAlarmEventTypeWire.FAILED,
                        occurredAtMillis = System.currentTimeMillis(),
                        failure =
                            WarmAlarmFailureWire(
                                code = WarmAlarmFailureCodeWire.AUDIO_PLAYBACK_FAILED,
                                message = e.message ?: "Unable to start media player.",
                            ),
                    ),
                )
            }
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
        }
    }

    private fun stopAudio() {
        mediaPlayer?.runCatching {
            stop()
            release()
        }
        mediaPlayer = null
    }

    private fun buildNotification(
        alarmId: Long,
        schedule: WarmAlarmScheduleWire?,
    ): Notification {
        val title = schedule?.notification?.title ?: "Alarm"
        val body = schedule?.notification?.body ?: ""
        val stopTitle = schedule?.notification?.stopActionTitle ?: "Stop"
        val snoozeTitle = schedule?.notification?.snoozeActionTitle

        val stopPendingIntent =
            PendingIntent.getService(
                this,
                (alarmId * 10 + 1).toInt(),
                Intent(this, WarmAlarmForegroundService::class.java).apply {
                    action = ACTION_STOP
                    putExtra(EXTRA_ALARM_ID, alarmId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val builder =
            NotificationCompat
                .Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setOngoing(true)
                .addAction(0, stopTitle, stopPendingIntent)

        if (snoozeTitle != null) {
            val snoozePendingIntent =
                PendingIntent.getService(
                    this,
                    (alarmId * 10 + 2).toInt(),
                    Intent(this, WarmAlarmForegroundService::class.java).apply {
                        action = ACTION_SNOOZE
                        putExtra(EXTRA_ALARM_ID, alarmId)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            builder.addAction(0, snoozeTitle, snoozePendingIntent)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "Warm Alarm",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Alarm notifications"
                }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
