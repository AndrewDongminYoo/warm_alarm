package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals

class WarmAlarmStoreTest {
    @Test
    fun recurrenceWeekdaysSurviveJsonRoundTrip() {
        val schedule =
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
                recurrence = WarmAlarmRecurrenceWire(weekdays = listOf(1, 3, 5)),
                androidFullScreenIntent = true,
            )

        val decoded = WarmAlarmStore.decode(WarmAlarmStore.encode(schedule))

        assertEquals(listOf(1L, 3L, 5L), decoded.recurrence?.weekdays)
    }
}
