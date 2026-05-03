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

        WarmAlarmStore
            .loadAll(context)
            .values
            .filter { it.scheduledAtMillis > now }
            .forEach { schedule ->
                val fireIntent =
                    Intent(context, WarmAlarmReceiver::class.java).apply {
                        action = WarmAlarmReceiver.ACTION_FIRE
                        putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, schedule.id)
                    }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pending = PendingIntent.getBroadcast(context, schedule.id.toInt(), fireIntent, flags)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, schedule.scheduledAtMillis, pending)
                } else {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, schedule.scheduledAtMillis, pending)
                }
            }
    }
}
