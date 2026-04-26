package com.andrew.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class WarmAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_FIRE = "com.andrew.alarm.ACTION_FIRE"
        const val EXTRA_ALARM_ID = "alarm_id"
    }

    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != ACTION_FIRE) return
        val alarmId = intent.getLongExtra(EXTRA_ALARM_ID, -1L)
        if (alarmId == -1L) return

        WarmAlarmPlugin.emitEventFromBackground(
            WarmAlarmEventWire(
                alarmId = alarmId,
                type = WarmAlarmEventTypeWire.FIRED,
                occurredAtMillis = System.currentTimeMillis(),
            ),
        )

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
}
