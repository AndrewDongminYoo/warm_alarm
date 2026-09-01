package com.andrew.alarm

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Which of the two ACTION_FIRE alarms a PendingIntent stands for. */
internal enum class WarmAlarmIntentKind {
    REGULAR,
    RETRIGGER,
}

/**
 * Single owner of every ACTION_FIRE PendingIntent this plugin creates.
 *
 * AlarmManager looks a PendingIntent up by request code plus [Intent.filterEquals],
 * and filterEquals ignores extras. The regular alarm and the wake-check retrigger
 * used to differ only by EXTRA_IS_RETRIGGER, so they resolved to one handle:
 * arming a retrigger re-targeted the pending next occurrence, and dismissing a
 * wake check cancelled it.
 *
 * REGULAR deliberately keeps the identity it had before this fix (no data), so an
 * alarm already scheduled by an older install stays cancellable after the update.
 * Only RETRIGGER carries a distinguishing Uri.
 */
internal object WarmAlarmPendingIntents {
    /** Null keeps [WarmAlarmIntentKind.REGULAR] on its pre-fix identity. */
    fun identityUri(
        packageName: String,
        alarmId: Long,
        kind: WarmAlarmIntentKind,
    ): String? =
        when (kind) {
            WarmAlarmIntentKind.REGULAR -> null
            WarmAlarmIntentKind.RETRIGGER -> "warm-alarm://$packageName/alarm/$alarmId/retrigger"
        }

    fun broadcast(
        context: Context,
        alarmId: Long,
        kind: WarmAlarmIntentKind,
        extraFlags: Int,
    ): PendingIntent? {
        val intent =
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = WarmAlarmReceiver.ACTION_FIRE
                identityUri(context.packageName, alarmId, kind)?.let { data = Uri.parse(it) }
                putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(WarmAlarmReceiver.EXTRA_IS_RETRIGGER, kind == WarmAlarmIntentKind.RETRIGGER)
            }
        return PendingIntent.getBroadcast(
            context,
            alarmId.toInt(),
            intent,
            extraFlags or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
