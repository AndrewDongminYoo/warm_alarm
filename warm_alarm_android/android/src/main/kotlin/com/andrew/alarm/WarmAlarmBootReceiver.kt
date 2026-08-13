package com.andrew.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class WarmAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.LOCKED_BOOT_COMPLETED"
        ) {
            return
        }

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()

        // Use device-protected storage during Direct Boot (before first unlock).
        val storeContext =
            if (intent.action == "android.intent.action.LOCKED_BOOT_COMPLETED" &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            ) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }

        WarmAlarmStore
            .loadAll(storeContext)
            .values
            .mapNotNull { schedule ->
                val activeSnoozeUntilMillis = WarmAlarmStore.activeSnoozeUntilMillis(storeContext, schedule.id)
                if (activeSnoozeUntilMillis != null && activeSnoozeUntilMillis <= now) {
                    WarmAlarmStore.clearActiveSnooze(storeContext, schedule.id)
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
                    WarmAlarmStore.reschedule(storeContext, schedule.id, fireAt)
                }
                schedule.id to fireAt
            }.forEach { (alarmId, fireAt) ->
                val fireIntent =
                    Intent(context, WarmAlarmReceiver::class.java).apply {
                        action = WarmAlarmReceiver.ACTION_FIRE
                        putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
                    }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pending = PendingIntent.getBroadcast(context, alarmId.toInt(), fireIntent, flags)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
                } else {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pending)
                }
            }
    }
}
