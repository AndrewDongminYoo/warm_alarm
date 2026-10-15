package com.andrew.alarm

import android.content.Context

internal object WarmAlarmIds {
    fun isSupported(id: Long): Boolean = id in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()

    fun error(id: Long): FlutterError =
        FlutterError(
            "INVALID_ALARM_ID",
            "Android alarm IDs must be between -2147483648 and 2147483647 inclusive; received $id.",
            id,
        )

    fun requireSupported(id: Long) {
        if (!isSupported(id)) throw error(id)
    }

    fun rejectUnsupported(
        context: Context,
        id: Long,
    ): Boolean {
        if (isSupported(id)) return false
        WarmAlarmPlugin.emitEventFromBackground(
            context,
            WarmAlarmEventWire(
                alarmId = id,
                type = WarmAlarmEventTypeWire.FAILED,
                occurredAtMillis = System.currentTimeMillis(),
                failure = WarmAlarmFailureWire(code = WarmAlarmFailureCodeWire.INVALID_ARGUMENTS, message = error(id).message),
            ),
        )
        return true
    }
}
