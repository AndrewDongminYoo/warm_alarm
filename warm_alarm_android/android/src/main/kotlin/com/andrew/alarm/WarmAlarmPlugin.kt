package com.andrew.alarm

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

internal interface AlarmSchedulingBackend {
    fun canScheduleExactAlarms(): Boolean

    fun scheduleLegacy(fireAtMillis: Long)

    fun scheduleExact(fireAtMillis: Long)

    fun scheduleInexact(fireAtMillis: Long)
}

private class AndroidAlarmSchedulingBackend(
    context: Context,
    alarmId: Long,
    isRetrigger: Boolean,
) : AlarmSchedulingBackend {
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    private val pendingIntent =
        WarmAlarmPendingIntents.broadcast(
            context = context,
            alarmId = alarmId,
            kind = if (isRetrigger) WarmAlarmIntentKind.RETRIGGER else WarmAlarmIntentKind.REGULAR,
            extraFlags = PendingIntent.FLAG_UPDATE_CURRENT,
        )!!

    override fun canScheduleExactAlarms(): Boolean = alarmManager.canScheduleExactAlarms()

    override fun scheduleLegacy(fireAtMillis: Long) {
        alarmManager.setExact(AlarmManager.RTC_WAKEUP, fireAtMillis, pendingIntent)
    }

    override fun scheduleExact(fireAtMillis: Long) {
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pendingIntent)
    }

    override fun scheduleInexact(fireAtMillis: Long) {
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pendingIntent)
    }
}

class WarmAlarmPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    WarmAlarmApi {
    private lateinit var context: Context
    private lateinit var alarmManager: AlarmManager
    private lateinit var notificationManager: NotificationManager
    private lateinit var eventsApi: WarmAlarmEventsApi
    private lateinit var pendingSnoozeReplay: PendingSnoozeEventReplay
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingNotificationPermissionCallback: ((Result<WarmAlarmRemediationResultWire>) -> Unit)? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        eventsApi = WarmAlarmEventsApi(binding.binaryMessenger)
        pendingSnoozeReplay =
            PendingSnoozeEventReplay(PendingSnoozeEventStore.create(context)) { event, callback ->
                mainHandler.post { eventsApi.emitEvent(event, callback) }
            }
        WarmAlarmApi.setUp(binding.binaryMessenger, this)
        pluginInstance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity(cancelPendingPermissionRequest = true)
        WarmAlarmApi.setUp(binding.binaryMessenger, null)
        pluginInstance = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity(cancelPendingPermissionRequest = false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity(cancelPendingPermissionRequest = true)
    }

    override fun initialize(callback: (Result<Unit>) -> Unit) {
        val now = System.currentTimeMillis()
        val recoverableAlarms =
            WarmAlarmStore.loadAll(context).values.mapNotNull { schedule ->
                val activeSnoozeUntilMillis = WarmAlarmStore.activeSnoozeUntilMillis(context, schedule.id)
                if (activeSnoozeUntilMillis != null && activeSnoozeUntilMillis <= now) {
                    WarmAlarmStore.clearActiveSnooze(context, schedule.id)
                }
                val fireAt =
                    WarmAlarmRecurrence.recoverableFireAt(
                        schedule.scheduledAtMillis,
                        schedule.recurrence?.weekdays,
                        now,
                        activeSnoozeUntilMillis = activeSnoozeUntilMillis,
                    ) ?: return@mapNotNull null
                val recoveringSnooze = activeSnoozeUntilMillis != null && activeSnoozeUntilMillis > now
                if (!recoveringSnooze && fireAt != schedule.scheduledAtMillis) {
                    WarmAlarmStore.reschedule(context, schedule.id, fireAt)
                }
                schedule.id to fireAt
            }
        if (recoverableAlarms.isNotEmpty()) {
            WarmAlarmKillWarningService.start(context)
        }
        recoverableAlarms
            .forEach { (alarmId, fireAt) ->
                val pending = alarmPendingIntent(alarmId, PendingIntent.FLAG_UPDATE_CURRENT, WarmAlarmIntentKind.REGULAR)!!
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
                } else {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
                }
            }
        pendingSnoozeReplay.drain()
        callback(Result.success(Unit))
    }

    override fun getCapabilities(callback: (Result<WarmAlarmCapabilitiesWire>) -> Unit) {
        callback(
            Result.success(
                WarmAlarmCapabilitiesWire(
                    exactScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
                    notificationScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
                    backgroundAudioPlayback = WarmAlarmSupportStatusWire.LIMITED,
                    fullScreenPresentation = WarmAlarmSupportStatusWire.SUPPORTED,
                    wakeCheck = WarmAlarmSupportStatusWire.SUPPORTED,
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

    override fun requestNotificationPermission(callback: (Result<WarmAlarmRemediationResultWire>) -> Unit) {
        if (currentPermissionState().notificationsGranted) {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.COMPLETED)))
            return
        }

        // Before Tiramisu notifications are granted at install time, so there is no request to
        // start; the caller has to send the user to settings instead.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.UNSUPPORTED)))
            return
        }

        // A rotated request still receives its result on the recreated activity, so a pending one
        // is never assumed abandoned here; duplicates wait and the callback is released when the
        // activity goes away for good.
        val attachedActivity = activity
        if (attachedActivity == null || pendingNotificationPermissionCallback != null) {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.UNAVAILABLE)))
            return
        }

        pendingNotificationPermissionCallback = callback
        attachedActivity.requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    override fun openReadinessSettings(
        reason: WarmAlarmReadinessReasonWire,
        callback: (Result<WarmAlarmRemediationResultWire>) -> Unit,
    ) {
        val intent =
            when (reason) {
                WarmAlarmReadinessReasonWire.NOTIFICATION_PERMISSION_DENIED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                            Settings.EXTRA_APP_PACKAGE,
                            context.packageName,
                        )
                    } else {
                        // The per-app notification screen only exists from O onwards, so older
                        // devices get the app details screen, which also exposes the toggle.
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${context.packageName}"),
                        )
                    }
                }

                WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:${context.packageName}"),
                        )
                    } else {
                        null
                    }
                }

                WarmAlarmReadinessReasonWire.FULL_SCREEN_PERMISSION_DENIED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        Intent(
                            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                            Uri.parse("package:${context.packageName}"),
                        )
                    } else {
                        null
                    }
                }

                else -> {
                    null
                }
            }
        if (intent == null) {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.UNSUPPORTED)))
            return
        }

        runCatching {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }.onSuccess {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.COMPLETED)))
        }.onFailure {
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.UNAVAILABLE)))
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) return false
        val callback = pendingNotificationPermissionCallback ?: return false
        pendingNotificationPermissionCallback = null
        // Android delivers empty arrays when the permission dialog is interrupted before the
        // user decides, which is a cancellation rather than a denial the caller can act on.
        val status =
            if (grantResults.isEmpty()) {
                WarmAlarmRemediationStatusWire.UNAVAILABLE
            } else {
                WarmAlarmRemediationStatusWire.COMPLETED
            }
        callback(Result.success(currentRemediationResult(status)))
        return true
    }

    override fun scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        callback: (Result<WarmAlarmScheduleResultWire>) -> Unit,
    ) {
        // A recurring alarm fires at the next matching weekday (AlarmManager is
        // single-shot; the fire receiver re-arms the following occurrence).
        val weekdays = schedule.recurrence?.weekdays
        val fireAtMillis =
            if (!weekdays.isNullOrEmpty()) {
                WarmAlarmRecurrence.nextOccurrence(
                    schedule.scheduledAtMillis,
                    weekdays,
                    System.currentTimeMillis(),
                ) ?: schedule.scheduledAtMillis
            } else {
                schedule.scheduledAtMillis
            }
        // Persist the actual fire time in one write so boot recovery and the
        // receiver's re-arm math read the scheduled occurrence, not the raw
        // request time.
        WarmAlarmStore.save(context, schedule.copy(scheduledAtMillis = fireAtMillis))
        // Keep a bare service alive while an alarm is scheduled so its
        // onTaskRemoved can post the kill warning if the app is swiped away
        // before the alarm rings.
        WarmAlarmKillWarningService.start(context)
        val pending = alarmPendingIntent(schedule.id, PendingIntent.FLAG_UPDATE_CURRENT, WarmAlarmIntentKind.REGULAR)!!
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
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pending)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pending)
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
        cancelScheduledAlarms(id)
        WarmAlarmForegroundService.requestCancelCurrentAlarm(context, id)
        if (WarmAlarmStore.loadAll(context).isEmpty()) {
            WarmAlarmKillWarningService.stop(context)
        }
        callback(Result.success(Unit))
    }

    override fun cancelAllAlarms(callback: (Result<Unit>) -> Unit) {
        WarmAlarmStore.loadAll(context).keys.forEach { id -> cancelScheduledAlarms(id) }
        WarmAlarmStore.clear(context)
        WarmAlarmKillWarningService.stop(context)
        WarmAlarmForegroundService.currentAlarmId?.let { id ->
            WarmAlarmForegroundService.requestCancelCurrentAlarm(context, id)
        }
        callback(Result.success(Unit))
    }

    override fun getScheduledAlarms(callback: (Result<List<WarmAlarmSnapshotWire>>) -> Unit) {
        val now = System.currentTimeMillis()
        val snapshots =
            WarmAlarmStore.loadAll(context).values.map { s ->
                WarmAlarmSnapshotWire(
                    id = s.id,
                    scheduledAtMillis =
                        WarmAlarmRecurrence.snapshotScheduledAtMillis(
                            s.scheduledAtMillis,
                            s.recurrence?.weekdays,
                            WarmAlarmStore.activeSnoozeUntilMillis(context, s.id),
                            now,
                        ),
                    notification = s.notification,
                    audio = s.audio,
                    recurrence = s.recurrence,
                    snooze = s.snooze,
                    wakeCheck = s.wakeCheck,
                    payload = s.payload,
                    androidFullScreenIntent = s.androidFullScreenIntent,
                )
            }
        callback(Result.success(snapshots))
    }

    override fun isRinging(
        alarmId: Long?,
        callback: (Result<Boolean>) -> Unit,
    ) {
        val ringing = WarmAlarmForegroundService.isRinging
        val currentId = WarmAlarmForegroundService.currentAlarmId
        callback(
            Result.success(
                if (alarmId == null) ringing else ringing && currentId == alarmId,
            ),
        )
    }

    override fun setKillWarning(
        title: String,
        body: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        context
            .getSharedPreferences(KILL_WARNING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString("title", title)
            .putString("body", body)
            .apply()
        callback(Result.success(Unit))
    }

    override fun clearKillWarning(callback: (Result<Unit>) -> Unit) {
        context
            .getSharedPreferences(KILL_WARNING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove("title")
            .remove("body")
            .apply()
        callback(Result.success(Unit))
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

    private fun currentRemediationResult(status: WarmAlarmRemediationStatusWire): WarmAlarmRemediationResultWire {
        val permissionState = currentPermissionState()
        return WarmAlarmRemediationResultWire(
            status = status,
            permissionState = permissionState,
            readiness = deriveReadiness(permissionState),
        )
    }

    private fun detachActivity(cancelPendingPermissionRequest: Boolean) {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        if (!cancelPendingPermissionRequest) return
        pendingNotificationPermissionCallback?.let { callback ->
            pendingNotificationPermissionCallback = null
            callback(Result.success(currentRemediationResult(WarmAlarmRemediationStatusWire.UNAVAILABLE)))
        }
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
        kind: WarmAlarmIntentKind,
    ): PendingIntent? = WarmAlarmPendingIntents.broadcast(context, alarmId, kind, extraFlags)

    // Cancels both identities: a wake-check retrigger can be armed alongside the
    // regular alarm, and it is a separate PendingIntent since the identity split.
    private fun cancelScheduledAlarms(alarmId: Long) {
        listOf(WarmAlarmIntentKind.REGULAR, WarmAlarmIntentKind.RETRIGGER).forEach { kind ->
            alarmPendingIntent(alarmId, PendingIntent.FLAG_NO_CREATE, kind)?.let { alarmManager.cancel(it) }
        }
    }

    companion object {
        const val KILL_WARNING_PREFS = "warm_alarm_kill_warning"
        private const val REQUEST_NOTIFICATION_PERMISSION = 39101
        private var pluginInstance: WarmAlarmPlugin? = null

        fun emitEventFromBackground(event: WarmAlarmEventWire) {
            val plugin = pluginInstance ?: return
            plugin.mainHandler.post {
                plugin.eventsApi.emitEvent(event) { /* ignore result */ }
            }
        }

        fun emitSnoozedEventFromBackground(
            context: Context,
            event: WarmAlarmEventWire,
        ) {
            val queued = PendingSnoozeEventStore.create(context).enqueue(event)
            val plugin = pluginInstance ?: return
            plugin.mainHandler.post {
                if (queued) {
                    plugin.pendingSnoozeReplay.drain()
                } else {
                    plugin.eventsApi.emitEvent(event) { _ -> }
                }
            }
        }

        internal fun rescheduleAlarm(
            context: Context,
            alarmId: Long,
            fireAtMillis: Long,
            isRetrigger: Boolean = false,
        ) {
            scheduleAlarm(
                backend = AndroidAlarmSchedulingBackend(context, alarmId, isRetrigger),
                fireAtMillis = fireAtMillis,
                sdkInt = Build.VERSION.SDK_INT,
            )
        }

        internal fun scheduleAlarm(
            backend: AlarmSchedulingBackend,
            fireAtMillis: Long,
            sdkInt: Int,
        ) {
            if (sdkInt < Build.VERSION_CODES.M) {
                backend.scheduleLegacy(fireAtMillis)
            } else if (sdkInt >= Build.VERSION_CODES.S && !backend.canScheduleExactAlarms()) {
                backend.scheduleInexact(fireAtMillis)
            } else {
                backend.scheduleExact(fireAtMillis)
            }
        }
    }
}
