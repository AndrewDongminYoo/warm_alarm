package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

// These assert the identity this plugin *asks* for, not that Android treats the
// two Intents as distinct. Intent.filterEquals is the load-bearing claim and no
// JVM test here can reach it; WarmAlarmPendingIntentsInstrumentedTest asserts it
// against the real framework registry and runs on an emulator in CI.
class WarmAlarmPendingIntentsTest {
    @Test
    fun regularAlarmsKeepTheIdentityTheyHadBeforeTheSplit() {
        val uri = WarmAlarmPendingIntents.identityUri("com.example.app", 7, WarmAlarmIntentKind.REGULAR)

        // A data-less Intent is what pre-0.1.2 installs scheduled with; changing
        // it would leave their pending alarms impossible to cancel after an update.
        assertNull(uri)
    }

    @Test
    fun aRetriggerDoesNotShareTheRegularAlarmIdentity() {
        val regular = WarmAlarmPendingIntents.identityUri("com.example.app", 7, WarmAlarmIntentKind.REGULAR)
        val retrigger = WarmAlarmPendingIntents.identityUri("com.example.app", 7, WarmAlarmIntentKind.RETRIGGER)

        assertNotEquals(regular, retrigger)
        assertEquals("warm-alarm://com.example.app/alarm/7/retrigger", retrigger)
    }

    @Test
    fun retriggerIdentitiesAreScopedToOneAlarm() {
        val first = WarmAlarmPendingIntents.identityUri("com.example.app", 7, WarmAlarmIntentKind.RETRIGGER)
        val second = WarmAlarmPendingIntents.identityUri("com.example.app", 8, WarmAlarmIntentKind.RETRIGGER)

        assertNotEquals(first, second)
    }

    @Test
    fun oneAlarmsThreeWakeCheckHandlesAreDistinct() {
        // The alarm itself, the pending wake check, and the prompt's dismiss
        // action are all broadcasts keyed by request code. Sharing one is the
        // defect this class exists to prevent.
        val alarmId = 7L
        val codes =
            setOf(
                alarmId.toInt(),
                WarmAlarmPendingIntents.wakeCheckRequestCode(alarmId),
                WarmAlarmPendingIntents.wakeCheckNotificationId(alarmId),
            )

        assertEquals(3, codes.size)
    }
}
