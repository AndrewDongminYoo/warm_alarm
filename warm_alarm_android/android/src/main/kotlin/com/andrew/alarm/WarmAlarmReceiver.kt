package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class WarmAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_FIRE = "com.andrew.alarm.ACTION_FIRE"
        const val ACTION_WAKE_CHECK_FIRE = "com.andrew.alarm.ACTION_WAKE_CHECK_FIRE"
        const val ACTION_WAKE_CHECK_DISMISS = "com.andrew.alarm.ACTION_WAKE_CHECK_DISMISS"
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_IS_RETRIGGER = "is_retrigger"
        private const val WAKE_CHECK_NOTIF_OFFSET = 20_000
    }

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        when (intent.action) {
            ACTION_FIRE -> handleAlarmFire(context, intent)
            ACTION_WAKE_CHECK_FIRE -> handleWakeCheckFire(context, intent)
            ACTION_WAKE_CHECK_DISMISS -> handleWakeCheckDismiss(context, intent)
        }
    }

    private fun handleAlarmFire(
        context: Context,
        intent: Intent,
    ) {
        val alarmId = intent.getLongExtra(EXTRA_ALARM_ID, -1L)
        if (alarmId == -1L) return
        val isRetrigger = intent.getBooleanExtra(EXTRA_IS_RETRIGGER, false)
        val schedule = WarmAlarmStore.load(context, alarmId)
        val payload = schedule?.payload

        if (isRetrigger) {
            WarmAlarmStore.incrementRetriggerCount(context, alarmId)
            WarmAlarmPlugin.emitEventFromBackground(
                WarmAlarmEventWire(
                    alarmId = alarmId,
                    type = WarmAlarmEventTypeWire.WAKE_CHECK_EXPIRED,
                    occurredAtMillis = System.currentTimeMillis(),
                ),
            )
            WarmAlarmPlugin.emitEventFromBackground(
                WarmAlarmEventWire(
                    alarmId = alarmId,
                    type = WarmAlarmEventTypeWire.RETRIGGERED,
                    occurredAtMillis = System.currentTimeMillis(),
                    payload = payload,
                ),
            )
        } else {
            WarmAlarmPlugin.emitEventFromBackground(
                WarmAlarmEventWire(
                    alarmId = alarmId,
                    type = WarmAlarmEventTypeWire.FIRED,
                    occurredAtMillis = System.currentTimeMillis(),
                    payload = payload,
                ),
            )

            // Re-arm the next occurrence for a recurring alarm. This runs in the
            // receiver (no Flutter engine required), so the series survives even
            // when the app process has been killed.
            val weekdays = schedule?.recurrence?.weekdays
            if (schedule != null && !weekdays.isNullOrEmpty()) {
                WarmAlarmRecurrence
                    .nextOccurrence(schedule.scheduledAtMillis, weekdays, System.currentTimeMillis())
                    ?.let { next ->
                        WarmAlarmStore.reschedule(context, alarmId, next)
                        WarmAlarmPlugin.rescheduleAlarm(context, alarmId, next)
                    }
            }
        }

        val serviceIntent =
            Intent(context, WarmAlarmForegroundService::class.java).apply {
                putExtra(EXTRA_ALARM_ID, alarmId)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }

    private fun handleWakeCheckFire(
        context: Context,
        intent: Intent,
    ) {
        val alarmId = intent.getLongExtra(EXTRA_ALARM_ID, -1L)
        if (alarmId == -1L) return
        val schedule = WarmAlarmStore.load(context, alarmId) ?: return

        WarmAlarmPlugin.emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.WAKE_CHECK_SHOWN,
                occurredAtMillis = System.currentTimeMillis(),
            ),
        )

        val maxRetriggers = (schedule.wakeCheck?.maxRetriggers ?: 1L).toInt()
        val retriggerCount = WarmAlarmStore.getRetriggerCount(context, alarmId)
        if (retriggerCount >= maxRetriggers) {
            WarmAlarmPlugin.emitEventFromBackground(
                WarmAlarmEventWire(
                    alarmId = alarmId,
                    type = WarmAlarmEventTypeWire.WAKE_CHECK_EXPIRED,
                    occurredAtMillis = System.currentTimeMillis(),
                ),
            )
            WarmAlarmStore.remove(context, alarmId)
            return
        }

        showWakeCheckNotification(context, alarmId, schedule)

        schedule.wakeCheck?.retriggerDelayMillis?.let { retriggerDelayMs ->
            WarmAlarmPlugin.rescheduleAlarm(
                context,
                alarmId,
                System.currentTimeMillis() + retriggerDelayMs,
                isRetrigger = true,
            )
        }
    }

    private fun showWakeCheckNotification(
        context: Context,
        alarmId: Long,
        schedule: WarmAlarmScheduleWire,
    ) {
        val dismissIntent =
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = ACTION_WAKE_CHECK_DISMISS
                putExtra(EXTRA_ALARM_ID, alarmId)
            }
        val dismissPending =
            PendingIntent.getBroadcast(
                context,
                (alarmId + WAKE_CHECK_NOTIF_OFFSET).toInt(),
                dismissIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val actionTitle = schedule.notification.stopActionTitle ?: "I'm awake"
        val notification =
            NotificationCompat
                .Builder(context, WarmAlarmForegroundService.CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(schedule.notification.title)
                .setContentText("Are you awake?")
                .addAction(0, actionTitle, dismissPending)
                .setAutoCancel(true)
                .build()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify((alarmId + WAKE_CHECK_NOTIF_OFFSET).toInt(), notification)
    }

    private fun handleWakeCheckDismiss(
        context: Context,
        intent: Intent,
    ) {
        val alarmId = intent.getLongExtra(EXTRA_ALARM_ID, -1L)
        if (alarmId == -1L) return

        val retriggerIntent =
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = ACTION_FIRE
                putExtra(EXTRA_ALARM_ID, alarmId)
                putExtra(EXTRA_IS_RETRIGGER, true)
            }
        val retriggerPending =
            PendingIntent.getBroadcast(
                context,
                alarmId.toInt(),
                retriggerIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
        retriggerPending?.let {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(it)
        }

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel((alarmId + WAKE_CHECK_NOTIF_OFFSET).toInt())

        WarmAlarmStore.remove(context, alarmId)
        WarmAlarmPlugin.emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.WAKE_CHECK_DISMISSED,
                occurredAtMillis = System.currentTimeMillis(),
            ),
        )
    }
}
