package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin

class WarmAlarmPlugin :
    FlutterPlugin,
    WarmAlarmApi {
    private lateinit var context: Context
    private lateinit var alarmManager: AlarmManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var eventsApi: WarmAlarmEventsApi
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        eventsApi = WarmAlarmEventsApi(binding.binaryMessenger)
        WarmAlarmApi.setUp(binding.binaryMessenger, this)
        pluginInstance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WarmAlarmApi.setUp(binding.binaryMessenger, null)
        pluginInstance = null
    }

    override fun getCapabilities(callback: (Result<WarmAlarmCapabilitiesWire>) -> Unit) {
        callback(
            Result.success(
                WarmAlarmCapabilitiesWire(
                    exactScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
                    notificationScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
                    backgroundAudioPlayback = WarmAlarmSupportStatusWire.LIMITED,
                    fullScreenPresentation = WarmAlarmSupportStatusWire.SUPPORTED,
                    wakeCheck = WarmAlarmSupportStatusWire.UNSUPPORTED,
                    liveActivity = WarmAlarmSupportStatusWire.UNSUPPORTED,
                ),
            ),
        )
    }

    override fun getPermissionState(callback: (Result<WarmAlarmPermissionStateWire>) -> Unit) {
        callback(Result.success(currentPermissionState()))
    }

    override fun getReadiness(callback: (Result<WarmAlarmReadinessWire>) -> Unit) {
        callback(Result.success(deriveReadiness(currentPermissionState())))
    }

    override fun scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        callback: (Result<WarmAlarmScheduleResultWire>) -> Unit,
    ) {
        WarmAlarmStore.save(context, schedule)
        val pending = alarmPendingIntent(schedule.id, PendingIntent.FLAG_UPDATE_CURRENT)!!
        val inexact = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()
        val readiness =
            if (inexact) {
                WarmAlarmReadinessWire(
                    level = WarmAlarmReadinessLevelWire.LIMITED,
                    reasons = listOf(WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED),
                )
            } else {
                deriveReadiness(currentPermissionState())
            }
        if (inexact) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, schedule.scheduledAtMillis, pending)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, schedule.scheduledAtMillis, pending)
        }
        emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = schedule.id,
                type = WarmAlarmEventTypeWire.SCHEDULED,
                occurredAtMillis = System.currentTimeMillis(),
            ),
        )
        callback(
            Result.success(
                WarmAlarmScheduleResultWire(
                    alarmId = schedule.id,
                    readiness = readiness,
                    warning =
                        if (inexact) {
                            WarmAlarmWarningWire(message = "SCHEDULE_EXACT_ALARM not granted; alarm may fire late.")
                        } else {
                            null
                        },
                ),
            ),
        )
    }

    override fun cancelAlarm(
        id: Long,
        callback: (Result<Unit>) -> Unit,
    ) {
        WarmAlarmStore.remove(context, id)
        val pending = alarmPendingIntent(id, PendingIntent.FLAG_NO_CREATE)
        pending?.let { alarmManager.cancel(it) }
        callback(Result.success(Unit))
    }

    override fun cancelAllAlarms(callback: (Result<Unit>) -> Unit) {
        WarmAlarmStore.loadAll(context).keys.forEach { id ->
            val pending = alarmPendingIntent(id, PendingIntent.FLAG_NO_CREATE)
            pending?.let { alarmManager.cancel(it) }
        }
        WarmAlarmStore.clear(context)
        callback(Result.success(Unit))
    }

    override fun getScheduledAlarms(callback: (Result<List<WarmAlarmSnapshotWire>>) -> Unit) {
        val snapshots =
            WarmAlarmStore.loadAll(context).values.map { s ->
                WarmAlarmSnapshotWire(id = s.id, scheduledAtMillis = s.scheduledAtMillis)
            }
        callback(Result.success(snapshots))
    }

    private fun currentPermissionState(): WarmAlarmPermissionStateWire {
        val notificationsGranted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.POST_NOTIFICATIONS,
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                NotificationManagerCompat.from(context).areNotificationsEnabled()
            }
        val exactAlarmGranted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alarmManager.canScheduleExactAlarms()
            } else {
                true
            }
        val fullScreenIntentGranted =
            if (Build.VERSION.SDK_INT >= 34) {
                notificationManager.canUseFullScreenIntent()
            } else {
                true
            }
        return WarmAlarmPermissionStateWire(
            notificationsGranted = notificationsGranted,
            exactAlarmGranted = exactAlarmGranted,
            fullScreenIntentGranted = fullScreenIntentGranted,
        )
    }

    private fun deriveReadiness(perm: WarmAlarmPermissionStateWire): WarmAlarmReadinessWire {
        val reasons =
            buildList {
                if (!perm.notificationsGranted) add(WarmAlarmReadinessReasonWire.NOTIFICATION_PERMISSION_DENIED)
                if (!perm.exactAlarmGranted) add(WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED)
                if (!perm.fullScreenIntentGranted) add(WarmAlarmReadinessReasonWire.FULL_SCREEN_PERMISSION_DENIED)
            }
        val level =
            when {
                reasons.isEmpty() -> WarmAlarmReadinessLevelWire.READY
                !perm.exactAlarmGranted -> WarmAlarmReadinessLevelWire.LIMITED
                else -> WarmAlarmReadinessLevelWire.LIMITED
            }
        return WarmAlarmReadinessWire(level = level, reasons = reasons)
    }

    private fun alarmPendingIntent(
        alarmId: Long,
        extraFlags: Int,
    ): PendingIntent? {
        val intent =
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = WarmAlarmReceiver.ACTION_FIRE
                putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
            }
        val flags = extraFlags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, alarmId.toInt(), intent, flags)
    }

    companion object {
        private var pluginInstance: WarmAlarmPlugin? = null

        fun emitEventFromBackground(event: WarmAlarmEventWire) {
            val plugin = pluginInstance ?: return
            plugin.mainHandler.post {
                plugin.eventsApi.emitEvent(event) { /* ignore result */ }
            }
        }

        fun rescheduleAlarm(
            context: Context,
            alarmId: Long,
            fireAtMillis: Long,
        ) {
            val plugin = pluginInstance ?: return
            val intent =
                Intent(context, WarmAlarmReceiver::class.java).apply {
                    action = WarmAlarmReceiver.ACTION_FIRE
                    putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
                }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pending = PendingIntent.getBroadcast(context, alarmId.toInt(), intent, flags)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !plugin.alarmManager.canScheduleExactAlarms()) {
                plugin.alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pending)
            } else {
                plugin.alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pending)
            }
        }
    }
}
