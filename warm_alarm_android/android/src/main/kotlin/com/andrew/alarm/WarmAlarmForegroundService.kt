package com.andrew.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.io.File

class WarmAlarmForegroundService : Service() {
    companion object {
        const val ACTION_STOP = "com.andrew.alarm.ACTION_STOP"
        const val ACTION_SNOOZE = "com.andrew.alarm.ACTION_SNOOZE"
        const val ACTION_CANCEL_CURRENT = "com.andrew.alarm.ACTION_CANCEL_CURRENT"
        const val EXTRA_ALARM_ID = WarmAlarmReceiver.EXTRA_ALARM_ID
        const val CHANNEL_ID = "warm_alarm_channel"
        private const val NOTIF_ID = 2001

        // internal so WarmAlarmKillWarningService reuses the exact same channel/id
        // — a swipe observed by both services then dedupes to one notification.
        internal const val KILL_WARNING_CHANNEL_ID = "warm_alarm_kill_warning_channel"
        internal const val KILL_WARNING_NOTIF_ID = 2002

        @Volatile var isRinging = false

        @Volatile var currentAlarmId: Long? = null

        fun requestCancelCurrentAlarm(
            context: Context,
            alarmId: Long,
        ) {
            if (!isRinging || currentAlarmId != alarmId) return
            context.startService(
                Intent(context, WarmAlarmForegroundService::class.java).apply {
                    action = ACTION_CANCEL_CURRENT
                    putExtra(EXTRA_ALARM_ID, alarmId)
                },
            )
        }

        /**
         * Sends the notification's Stop action for [alarmId], so handleStop
         * emits STOPPED and arms the wake-check exactly as a tap on Stop does.
         * Returns false and sends nothing when [alarmId] is not the alarm ringing.
         */
        fun requestStop(
            context: Context,
            alarmId: Long,
        ): Boolean {
            if (!isRinging || currentAlarmId != alarmId) return false
            context.startService(
                Intent(context, WarmAlarmForegroundService::class.java).apply {
                    action = ACTION_STOP
                    putExtra(EXTRA_ALARM_ID, alarmId)
                },
            )
            return true
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var currentSchedule: WarmAlarmScheduleWire? = null
    private var vibrationController: WarmAlarmVibrationController? = null
    private val fadeStepHandler = Handler(Looper.getMainLooper())
    private val volumeEnforcerHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        createKillWarningChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent == null || !intent.hasExtra(EXTRA_ALARM_ID)) {
            if (!isRinging) stopSelf()
            return START_NOT_STICKY
        }
        val action = intent.action
        val alarmId = intent.getLongExtra(EXTRA_ALARM_ID, -1L)
        if (WarmAlarmIds.rejectUnsupported(this, alarmId)) {
            if (!isRinging) stopSelf()
            return START_NOT_STICKY
        }

        when (action) {
            ACTION_STOP -> handleStop(alarmId)
            ACTION_SNOOZE -> handleSnooze(alarmId)
            ACTION_CANCEL_CURRENT -> handleCancelCurrentAlarm(alarmId)
            else -> handleFire(alarmId)
        }
        return START_NOT_STICKY
    }

    private fun handleFire(alarmId: Long) {
        val schedule = WarmAlarmStore.load(this, alarmId)
        // The newest alarm replaces playback, without performing Stop or Snooze on the old schedule.
        stopAudio()
        currentSchedule = schedule
        isRinging = true
        currentAlarmId = alarmId
        startForeground(NOTIF_ID, buildNotification(alarmId, schedule))
        startAudio(alarmId, schedule)
    }

    private fun handleStop(alarmId: Long) {
        val schedule = currentSchedule ?: WarmAlarmStore.load(this, alarmId)
        isRinging = false
        currentAlarmId = null
        stopAudio()
        WarmAlarmPlugin.emitEventFromBackground(
            this,
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.STOPPED,
                occurredAtMillis = System.currentTimeMillis(),
                payload = schedule?.payload,
            ),
        )
        val wakeCheckDelay = schedule?.wakeCheck?.checkDelayMillis
        val maxRetriggers = (schedule?.wakeCheck?.maxRetriggers ?: 1L).toInt()
        val retriggerCount = WarmAlarmStore.getRetriggerCount(this, alarmId)
        // A recurring alarm keeps its stored schedule: the next occurrence was
        // re-armed when it fired, and only cancelAlarm() tears down the series.
        val isRecurring = schedule?.recurrence?.weekdays.isNullOrEmpty() == false
        if (wakeCheckDelay != null && retriggerCount < maxRetriggers) {
            scheduleWakeCheck(alarmId, System.currentTimeMillis() + wakeCheckDelay)
        } else {
            // No further check is coming, so the cycle is over for this
            // occurrence. Reset it: otherwise a recurring alarm carries a count
            // already at maxRetriggers into every later occurrence and skips
            // its wake check for good.
            WarmAlarmPendingIntents.endWakeCheckCycle(this, alarmId)
            if (!isRecurring) WarmAlarmStore.remove(this, alarmId)
        }
        finishForegroundNotification(alarmId, schedule)
        stopSelf()
    }

    private fun handleCancelCurrentAlarm(alarmId: Long) {
        if (currentAlarmId != alarmId) return
        isRinging = false
        currentAlarmId = null
        currentSchedule = null
        stopAudio()
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    private fun scheduleWakeCheck(
        alarmId: Long,
        checkAtMillis: Long,
    ) {
        val pending = WarmAlarmPendingIntents.wakeCheckTrigger(this, alarmId, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, checkAtMillis, pending)
        } else {
            am.set(android.app.AlarmManager.RTC_WAKEUP, checkAtMillis, pending)
        }
    }

    private fun handleSnooze(alarmId: Long) {
        val schedule = currentSchedule ?: WarmAlarmStore.load(this, alarmId)
        isRinging = false
        currentAlarmId = null
        stopAudio()
        val snoozeDurationMillis = schedule?.snooze?.durationMillis ?: (5L * 60 * 1000)
        val fireAt = System.currentTimeMillis() + snoozeDurationMillis

        if (schedule != null) {
            WarmAlarmStore.setActiveSnooze(this, alarmId, fireAt)
        }
        WarmAlarmPlugin.rescheduleAlarm(this, alarmId, fireAt)

        WarmAlarmPlugin.emitSnoozedEventFromBackground(
            this,
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.SNOOZED,
                occurredAtMillis = System.currentTimeMillis(),
                snoozeDurationMillis = snoozeDurationMillis,
                payload = schedule?.payload,
            ),
        )
        finishForegroundNotification(alarmId, schedule)
        stopSelf()
    }

    private fun finishForegroundNotification(
        alarmId: Long,
        schedule: WarmAlarmScheduleWire?,
    ) {
        if (schedule?.notification?.keepNotificationAfterAlarmEnds != true) {
            @Suppress("DEPRECATION")
            stopForeground(true)
            return
        }
        val retained = buildNotification(alarmId, schedule)
        // Completed notifications retain their content without stale alarm controls or another full-screen launch.
        retained.actions = emptyArray()
        retained.fullScreenIntent = null
        retained.flags =
            (
                retained.flags and
                    (Notification.FLAG_FOREGROUND_SERVICE or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR).inv()
            ) or
            Notification.FLAG_ONLY_ALERT_ONCE
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Detach first so the service no longer owns the record when the retained content replaces it.
            stopForeground(STOP_FOREGROUND_DETACH)
            notifications.notify(NOTIF_ID, retained)
        } else {
            // This is a new notification record, so ONLY_ALERT_ONCE cannot silence its first alert.
            retained.priority = Notification.PRIORITY_LOW
            retained.sound = null
            retained.vibrate = null
            retained.defaults = 0
            @Suppress("DEPRECATION")
            stopForeground(true)
            notifications.notify(NOTIF_ID, retained)
        }
    }

    private fun startAudio(
        alarmId: Long,
        schedule: WarmAlarmScheduleWire?,
    ) {
        val audio = schedule?.audio
        val fadeSteps = WarmAlarmAudioPolicy.resolveFadeSteps(audio?.fadeSteps, audio?.fadeInDurationMillis, audio?.volume)
        val zeroStep = fadeSteps?.firstOrNull { it.timeMillis == 0L }
        val initialVolume =
            (
                zeroStep?.volume?.toFloat()
                    ?: audio?.volume?.toFloat()
                    ?: 1f
            ).coerceIn(0f, 1f)
        val filePath = audio?.filePath
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = filePath,
                assetPath = audio?.assetPath,
                loop = audio?.loop ?: true,
                canReadCredentialProtectedFiles = WarmAlarmDirectBoot.canReadCredentialProtectedFiles(this),
                fileReadableDuringDirectBoot = !filePath.isNullOrEmpty() && File(filePath).canRead(),
            )

        try {
            WarmAlarmAudioPolicy.enforceSystemVolume(audio?.volumeEnforced == true) { boostAlarmVolume() }
            vibrationController().start(audio?.vibrate == true)
            mediaPlayer =
                when (selection.source) {
                    WarmAlarmAudioSource.FILE -> {
                        createPlayer(volume = initialVolume, loop = selection.loop) {
                            setDataSource(this@WarmAlarmForegroundService, Uri.fromFile(File(requireNotNull(selection.path))))
                        }
                    }

                    WarmAlarmAudioSource.ASSET -> {
                        createPlayer(volume = initialVolume, loop = selection.loop) {
                            assets.openFd("flutter_assets/${selection.path}").use { descriptor ->
                                setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                            }
                        }
                    }

                    WarmAlarmAudioSource.DEFAULT_ALARM -> {
                        val uri =
                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        createPlayer(volume = initialVolume, loop = selection.loop) {
                            setDataSource(this@WarmAlarmForegroundService, uri)
                        }
                    }
                }
            if (fadeSteps != null) applyFadeSteps(fadeSteps)
            if (audio?.volumeEnforced == true) startVolumeEnforcer()
        } catch (e: Exception) {
            stopAudio()
            WarmAlarmPlugin.emitEventFromBackground(
                this,
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
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
        }
    }

    private fun createPlayer(
        volume: Float,
        loop: Boolean,
        configure: MediaPlayer.() -> Unit,
    ): MediaPlayer {
        val player = MediaPlayer()
        try {
            player.configure()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                player.setAudioAttributes(
                    AudioAttributes
                        .Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
            } else {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_ALARM)
            }
            player.isLooping = loop
            player.setVolume(volume, volume)
            player.prepare()
            player.start()
            return player
        } catch (e: Exception) {
            runCatching { player.release() }
            throw e
        }
    }

    private fun boostAlarmVolume() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
    }

    private fun stopAudio() {
        fadeStepHandler.removeCallbacksAndMessages(null)
        volumeEnforcerHandler.removeCallbacksAndMessages(null)
        vibrationController?.stop()
        mediaPlayer?.runCatching {
            try {
                stop()
            } finally {
                release()
            }
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
            WarmAlarmPendingIntents.serviceAction(
                this,
                alarmId,
                ACTION_STOP,
                PendingIntent.FLAG_UPDATE_CURRENT,
            )

        val iconResId =
            schedule
                ?.notification
                ?.androidIcon
                ?.let { name -> resources.getIdentifier(name, "drawable", packageName).takeIf { it != 0 } }
                ?: android.R.drawable.ic_lock_idle_alarm

        val builder =
            NotificationCompat
                .Builder(this, CHANNEL_ID)
                .setSmallIcon(iconResId)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setOngoing(true)
                .addAction(0, stopTitle, stopPendingIntent)

        if (snoozeTitle != null) {
            val snoozePendingIntent =
                WarmAlarmPendingIntents.serviceAction(
                    this,
                    alarmId,
                    ACTION_SNOOZE,
                    PendingIntent.FLAG_UPDATE_CURRENT,
                )
            builder.addAction(0, snoozeTitle, snoozePendingIntent)
        }

        schedule?.notification?.androidIconColor?.let { builder.setColor(it.toInt()) }

        if (schedule?.androidFullScreenIntent != false) {
            val launchIntent =
                packageManager
                    .getLaunchIntentForPackage(packageName)
                    ?.apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra(EXTRA_ALARM_ID, alarmId)
                    }
            if (launchIntent != null) {
                val fullScreenPendingIntent =
                    PendingIntent.getActivity(
                        this,
                        alarmId.toInt(),
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                builder.setFullScreenIntent(fullScreenPendingIntent, true)
            }
        }

        return builder.build()
    }

    private fun applyFadeSteps(steps: List<WarmAlarmVolumeFadeStepWire>) {
        for (step in steps) {
            if (step.timeMillis == 0L) continue
            val vol = step.volume.toFloat().coerceIn(0f, 1f)
            fadeStepHandler.postDelayed({
                mediaPlayer?.setVolume(vol, vol)
            }, step.timeMillis)
        }
    }

    private fun startVolumeEnforcer() {
        val enforcer =
            object : Runnable {
                override fun run() {
                    boostAlarmVolume()
                    volumeEnforcerHandler.postDelayed(this, 1_000L)
                }
            }
        volumeEnforcerHandler.post(enforcer)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (isRinging) {
            val prefs = getSharedPreferences(WarmAlarmPlugin.KILL_WARNING_PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("title", null)
            val body = prefs.getString("body", null)
            if (title != null && body != null) {
                postKillWarningNotification(title, body)
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun postKillWarningNotification(
        title: String,
        body: String,
    ) {
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

    private fun createKillWarningChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    KILL_WARNING_CHANNEL_ID,
                    "Alarm Kill Warning",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notifies when the app is killed while an alarm is active"
                }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
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
        isRinging = false
        currentAlarmId = null
        stopAudio()
        super.onDestroy()
    }

    private fun vibrationController(): WarmAlarmVibrationController =
        vibrationController ?: WarmAlarmVibrationController(AndroidWarmAlarmVibrationBackend(this)).also {
            vibrationController = it
        }
}
