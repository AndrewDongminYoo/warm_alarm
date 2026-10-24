package com.andrew.alarm

import android.content.Context
import android.content.res.Resources
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmReceiverTest {
    private fun schedule(
        weekdays: List<Long>? = null,
        stopActionTitle: String? = null,
        androidIcon: String? = null,
        wakeCheck: WarmAlarmWakeCheckWire? = null,
    ) = WarmAlarmScheduleWire(
        id = 42,
        scheduledAtMillis = 1_234,
        notification =
            WarmAlarmNotificationWire(
                title = "Wake up",
                body = "Good morning",
                stopActionTitle = stopActionTitle,
                androidIcon = androidIcon,
                keepNotificationAfterAlarmEnds = false,
            ),
        audio =
            WarmAlarmAudioWire(
                loop = true,
                vibrate = true,
                volumeEnforced = false,
            ),
        recurrence = weekdays?.let { WarmAlarmRecurrenceWire(weekdays = it) },
        wakeCheck = wakeCheck,
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

    @Test
    fun anUnconfiguredPromptKeepsTheEnglishDefaults() {
        val prompt = WarmAlarmReceiver.wakeCheckPrompt(schedule(wakeCheck = WarmAlarmWakeCheckWire(checkDelayMillis = 60_000)))

        assertEquals(WarmAlarmReceiver.WakeCheckPrompt("Wake up", "Are you awake?", "I'm awake"), prompt)
    }

    @Test
    fun anUnconfiguredConfirmLabelStillFallsBackToTheStopLabel() {
        val prompt =
            WarmAlarmReceiver.wakeCheckPrompt(
                schedule(stopActionTitle = "Dismiss alarm", wakeCheck = WarmAlarmWakeCheckWire(checkDelayMillis = 60_000)),
            )

        assertEquals("Dismiss alarm", prompt.confirmActionTitle)
    }

    @Test
    fun aConfiguredPromptUsesTheHostText() {
        val prompt =
            WarmAlarmReceiver.wakeCheckPrompt(
                schedule(
                    stopActionTitle = "Dismiss alarm",
                    wakeCheck =
                        WarmAlarmWakeCheckWire(
                            checkDelayMillis = 60_000,
                            title = "기상 확인",
                            body = "일어나셨나요?",
                            confirmActionTitle = "일어났어요",
                        ),
                ),
            )

        assertEquals(WarmAlarmReceiver.WakeCheckPrompt("기상 확인", "일어나셨나요?", "일어났어요"), prompt)
    }

    @Test
    fun thePromptUsesTheScheduleIconWhenItResolves() {
        val context = iconContext(mapOf("ic_alarm" to 0x7f080001))

        assertEquals(0x7f080001, WarmAlarmReceiver.wakeCheckIcon(context, schedule(androidIcon = "ic_alarm").notification))
    }

    @Test
    fun thePromptKeepsTheSystemAlertIconWhenNoIconResolves() {
        val context = iconContext(emptyMap())

        assertEquals(
            android.R.drawable.ic_dialog_alert,
            WarmAlarmReceiver.wakeCheckIcon(context, schedule(androidIcon = "ic_missing").notification),
        )
        assertEquals(android.R.drawable.ic_dialog_alert, WarmAlarmReceiver.wakeCheckIcon(context, schedule().notification))
    }

    private fun iconContext(drawables: Map<String, Int>): Context {
        val context = Mockito.mock(Context::class.java)
        val resources = Mockito.mock(Resources::class.java)
        Mockito.`when`(context.resources).thenReturn(resources)
        Mockito.`when`(context.packageName).thenReturn("com.example.host")
        drawables.forEach { (name, id) ->
            Mockito.`when`(resources.getIdentifier(name, "drawable", "com.example.host")).thenReturn(id)
        }
        return context
    }
}
