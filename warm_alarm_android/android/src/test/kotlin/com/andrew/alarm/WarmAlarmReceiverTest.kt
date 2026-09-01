package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmReceiverTest {
    private fun schedule(weekdays: List<Long>?) =
        WarmAlarmScheduleWire(
            id = 42,
            scheduledAtMillis = 1_234,
            notification =
                WarmAlarmNotificationWire(
                    title = "Wake up",
                    body = "Good morning",
                    keepNotificationAfterAlarmEnds = false,
                ),
            audio =
                WarmAlarmAudioWire(
                    loop = true,
                    vibrate = true,
                    volumeEnforced = false,
                ),
            recurrence = weekdays?.let { WarmAlarmRecurrenceWire(weekdays = it) },
            androidFullScreenIntent = true,
        )

    @Test
    fun aRecurringScheduleSurvivesWakeCheckCompletion() {
        // handleAlarmFire already armed the next occurrence; removing the
        // schedule here would take the series with it.
        assertFalse(WarmAlarmReceiver.wakeCheckMayRemoveSchedule(schedule(listOf(1L, 3L, 5L))))
    }

    @Test
    fun aOneShotScheduleIsReleasedOnWakeCheckCompletion() {
        assertTrue(WarmAlarmReceiver.wakeCheckMayRemoveSchedule(schedule(null)))
        assertTrue(WarmAlarmReceiver.wakeCheckMayRemoveSchedule(schedule(emptyList())))
    }

    @Test
    fun aScheduleThatCouldNotBeReadIsLeftAlone() {
        // WarmAlarmStore.remove persists the map it just read, so removing on
        // a read that came back empty writes an empty list over every schedule.
        assertFalse(WarmAlarmReceiver.wakeCheckMayRemoveSchedule(null))
    }
}
