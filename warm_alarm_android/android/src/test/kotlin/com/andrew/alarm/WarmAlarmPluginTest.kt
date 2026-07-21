package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals

class WarmAlarmPluginTest {
    @Test
    fun alarmSchedulingDoesNotRequireAnAttachedFlutterEngine() {
        val backend = FakeAlarmSchedulingBackend()

        WarmAlarmPlugin.scheduleAlarm(
            backend = backend,
            fireAtMillis = 1_234,
            sdkInt = 30,
        )

        assertEquals(listOf(1_234L), backend.exactSchedules)
        assertEquals(emptyList(), backend.inexactSchedules)
    }

    @Test
    fun preMarshmallowSchedulingUsesTheLegacyExactApi() {
        val backend = FakeAlarmSchedulingBackend()

        WarmAlarmPlugin.scheduleAlarm(
            backend = backend,
            fireAtMillis = 1_234,
            sdkInt = 22,
        )

        assertEquals(listOf(1_234L), backend.legacySchedules)
        assertEquals(emptyList(), backend.exactSchedules)
    }
}

private class FakeAlarmSchedulingBackend : AlarmSchedulingBackend {
    val legacySchedules = mutableListOf<Long>()
    val exactSchedules = mutableListOf<Long>()
    val inexactSchedules = mutableListOf<Long>()

    override fun canScheduleExactAlarms(): Boolean = true

    override fun scheduleLegacy(fireAtMillis: Long) {
        legacySchedules += fireAtMillis
    }

    override fun scheduleExact(fireAtMillis: Long) {
        exactSchedules += fireAtMillis
    }

    override fun scheduleInexact(fireAtMillis: Long) {
        inexactSchedules += fireAtMillis
    }
}
