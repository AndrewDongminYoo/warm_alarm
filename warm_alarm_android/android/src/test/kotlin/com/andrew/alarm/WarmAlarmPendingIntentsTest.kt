package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

// ponytail: these assert the identity this plugin *asks* for, not that Android
// treats the two Intents as distinct. Intent.filterEquals is the load-bearing
// claim and no JVM test here can reach it. The device check under "Wake-check"
// in README.md is what actually verifies it.
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
}
