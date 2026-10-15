package com.andrew.alarm

import android.app.PendingIntent
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

/**
 * The claim [WarmAlarmPendingIntentsTest] cannot make.
 *
 * AlarmManager looks a PendingIntent up by request code plus [android.content.Intent.filterEquals],
 * and filterEquals ignores extras. Both kinds here carry request code `alarmId`, so the data Uri is
 * the only thing that can separate them, and only the framework's own registry can say whether it
 * does. The JVM tests assert the identity this plugin asks for; these assert that Android agrees.
 *
 * Both tests fail if [WarmAlarmPendingIntents.identityUri] goes back to returning null for
 * [WarmAlarmIntentKind.RETRIGGER], which is the pre-0.1.2 shape.
 */
class WarmAlarmPendingIntentsInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    // Well outside the ids any other test or the example app schedules, so a leaked
    // registration cannot make this pass or fail for the wrong reason.
    private val alarmId = 987_654L
    private val boundaryIds = listOf(Int.MIN_VALUE.toLong(), -1L, 0L, 1L, Int.MAX_VALUE.toLong())

    @Before
    fun clearBefore() = clearRegistry()

    @After
    fun clearAfter() = clearRegistry()

    private fun clearRegistry() {
        for (id in boundaryIds + alarmId) {
            for (kind in WarmAlarmIntentKind.entries) {
                WarmAlarmPendingIntents.broadcast(context, id, kind, PendingIntent.FLAG_NO_CREATE)?.cancel()
            }
            WarmAlarmPendingIntents.wakeCheckTrigger(context, id, PendingIntent.FLAG_NO_CREATE)?.cancel()
            for (action in listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE)) {
                WarmAlarmPendingIntents.serviceAction(context, id, action, PendingIntent.FLAG_NO_CREATE)?.cancel()
            }
        }
    }

    @Test
    fun boundaryAlarmsAndWakeChecksRemainDistinctInTheRegistry() {
        val handles =
            boundaryIds.flatMap { id ->
                listOf(
                    WarmAlarmPendingIntents.broadcast(context, id, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_UPDATE_CURRENT)!!,
                    WarmAlarmPendingIntents.broadcast(context, id, WarmAlarmIntentKind.RETRIGGER, PendingIntent.FLAG_UPDATE_CURRENT)!!,
                    WarmAlarmPendingIntents.wakeCheckTrigger(context, id, PendingIntent.FLAG_UPDATE_CURRENT)!!,
                )
            }
        assertEquals(boundaryIds.size * 3, handles.toSet().size)

        WarmAlarmPendingIntents.broadcast(context, -1, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_NO_CREATE)!!.cancel()

        assertNull(WarmAlarmPendingIntents.broadcast(context, -1, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_NO_CREATE))
        assertNotNull(WarmAlarmPendingIntents.broadcast(context, -1, WarmAlarmIntentKind.RETRIGGER, PendingIntent.FLAG_NO_CREATE))
        for (id in boundaryIds.filter { it != -1L }) {
            assertNotNull(WarmAlarmPendingIntents.broadcast(context, id, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_NO_CREATE))
        }
    }

    @Test
    fun outOfRangeAliasIsRejectedWithoutReplacingTheSupportedHandle() {
        val legacy = legacyRegular(0)
        try {
            // Positive control: the real framework aliases the old 64-bit input.
            assertEquals(legacy, legacyRegular(4_294_967_296L))
            val regular = WarmAlarmPendingIntents.broadcast(context, 0, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_UPDATE_CURRENT)
            assertEquals(legacy, regular)
            val wakeCheck = WarmAlarmPendingIntents.wakeCheckTrigger(context, 0, PendingIntent.FLAG_UPDATE_CURRENT)

            for (id in listOf(Int.MIN_VALUE.toLong() - 1, Int.MAX_VALUE.toLong() + 1, 4_294_967_296L, Long.MIN_VALUE, Long.MAX_VALUE)) {
                assertThrows(FlutterError::class.java) {
                    WarmAlarmPendingIntents.broadcast(context, id, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_UPDATE_CURRENT)
                }
                assertThrows(
                    FlutterError::class.java,
                ) { WarmAlarmPendingIntents.wakeCheckTrigger(context, id, PendingIntent.FLAG_UPDATE_CURRENT) }
            }

            assertEquals(regular, WarmAlarmPendingIntents.broadcast(context, 0, WarmAlarmIntentKind.REGULAR, PendingIntent.FLAG_NO_CREATE))
            assertEquals(wakeCheck, WarmAlarmPendingIntents.wakeCheckTrigger(context, 0, PendingIntent.FLAG_NO_CREATE))
        } finally {
            legacy?.cancel()
        }
    }

    @Test
    fun serviceActionsDoNotRetargetEachOtherOrLegacyActions() {
        val legacy =
            PendingIntent.getService(
                context,
                1,
                Intent(context, WarmAlarmForegroundService::class.java).apply {
                    action = WarmAlarmForegroundService.ACTION_STOP
                    putExtra(WarmAlarmForegroundService.EXTRA_ALARM_ID, 0L)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        try {
            val handles =
                boundaryIds.flatMap { id ->
                    listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE).map { action ->
                        WarmAlarmPendingIntents.serviceAction(context, id, action, PendingIntent.FLAG_UPDATE_CURRENT)!!
                    }
                }
            assertEquals(boundaryIds.size * 2, handles.toSet().size)
            assertNotEquals(
                legacy,
                WarmAlarmPendingIntents.serviceAction(context, 1, WarmAlarmForegroundService.ACTION_STOP, PendingIntent.FLAG_NO_CREATE),
            )
            WarmAlarmPendingIntents
                .serviceAction(
                    context,
                    0,
                    WarmAlarmForegroundService.ACTION_STOP,
                    PendingIntent.FLAG_NO_CREATE,
                )!!
                .cancel()
            assertNotNull(
                WarmAlarmPendingIntents.serviceAction(
                    context,
                    Int.MIN_VALUE.toLong(),
                    WarmAlarmForegroundService.ACTION_STOP,
                    PendingIntent.FLAG_NO_CREATE,
                ),
            )
            assertNotNull(
                WarmAlarmPendingIntents.serviceAction(context, 0, WarmAlarmForegroundService.ACTION_SNOOZE, PendingIntent.FLAG_NO_CREATE),
            )
        } finally {
            legacy?.cancel()
        }
    }

    private fun legacyRegular(id: Long): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            id.toInt(),
            Intent(context, WarmAlarmReceiver::class.java).apply {
                action = WarmAlarmReceiver.ACTION_FIRE
                putExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun lookUp(kind: WarmAlarmIntentKind): PendingIntent? =
        WarmAlarmPendingIntents.broadcast(context, alarmId, kind, PendingIntent.FLAG_NO_CREATE)

    private fun register(kind: WarmAlarmIntentKind): PendingIntent? =
        WarmAlarmPendingIntents.broadcast(context, alarmId, kind, PendingIntent.FLAG_UPDATE_CURRENT)

    @Test
    fun aRegisteredRegularAlarmDoesNotAnswerARetriggerLookup() {
        assertNotNull(register(WarmAlarmIntentKind.REGULAR))

        // Before 0.1.2 this lookup returned the regular alarm's own handle, so arming a
        // retrigger re-targeted the recurring alarm's pending next occurrence.
        assertNull(lookUp(WarmAlarmIntentKind.RETRIGGER))
    }

    @Test
    fun cancellingARetriggerLeavesTheRegularAlarmRegistered() {
        assertNotNull(register(WarmAlarmIntentKind.REGULAR))
        val retrigger = register(WarmAlarmIntentKind.RETRIGGER)
        assertNotNull(retrigger)

        retrigger!!.cancel()

        assertNull(lookUp(WarmAlarmIntentKind.RETRIGGER))
        // Before 0.1.2 the two were one handle, so ending a wake-check cycle cancelled the
        // series along with the retrigger. That is the success path, not a failure path.
        assertNotNull(lookUp(WarmAlarmIntentKind.REGULAR))
    }
}
