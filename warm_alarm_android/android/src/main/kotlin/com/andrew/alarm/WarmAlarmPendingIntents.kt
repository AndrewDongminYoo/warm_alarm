package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
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
    private const val WAKE_CHECK_NOTIF_OFFSET = 20_000
    private const val WAKE_CHECK_PENDING_OFFSET = 30_000

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

    /** Request code of the pending wake check for [alarmId]. */
    fun wakeCheckRequestCode(alarmId: Long): Int = (alarmId + WAKE_CHECK_PENDING_OFFSET).toInt()

    /** Notification id of the wake-check prompt for [alarmId]. */
    fun wakeCheckNotificationId(alarmId: Long): Int = (alarmId + WAKE_CHECK_NOTIF_OFFSET).toInt()

    fun wakeCheckTrigger(
        context: Context,
        alarmId: Long,
        extraFlags: Int,
    ): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            wakeCheckRequestCode(alarmId),
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = WarmAlarmReceiver.ACTION_WAKE_CHECK_FIRE
                putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, alarmId)
            },
            extraFlags or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * Tears down a wake-check cycle completely: the pending check, the retrigger
     * it would arm, the prompt it may already be showing, and the retrigger
     * count. Every path that ends a cycle goes through here, so none of them can
     * leave one part of it armed against a schedule it no longer belongs to.
     */
    fun endWakeCheckCycle(
        context: Context,
        alarmId: Long,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        wakeCheckTrigger(context, alarmId, PendingIntent.FLAG_NO_CREATE)?.let { alarmManager.cancel(it) }
        broadcast(context, alarmId, WarmAlarmIntentKind.RETRIGGER, PendingIntent.FLAG_NO_CREATE)
            ?.let { alarmManager.cancel(it) }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(wakeCheckNotificationId(alarmId))
        WarmAlarmStore.clearRetriggerCount(context, alarmId)
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
