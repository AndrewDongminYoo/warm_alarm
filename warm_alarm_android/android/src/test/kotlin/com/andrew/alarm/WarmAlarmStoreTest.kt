package com.andrew.alarm

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.mockito.ArgumentCaptor
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

class WarmAlarmStoreTest {
    @Test
    fun malformedRootJsonIsReplacedWithAnEmptyScheduleList() {
        val harness = StorePreferencesHarness("{")

        val schedules = WarmAlarmStore.loadAll(harness.context)

        assertEquals(emptyMap(), schedules)
        assertEquals(0, JSONArray(harness.lastPersistedJson()).length())
    }

    @Test
    fun malformedArrayEntriesAreSkippedAndValidSchedulesArePersisted() {
        val validSchedule = schedule(id = 42)
        val storedJson =
            JSONArray()
                .put(WarmAlarmStore.encode(validSchedule))
                .put("not-an-object")
                .put(org.json.JSONObject().put("id", 99))
                .toString()
        val harness = StorePreferencesHarness(storedJson)

        val schedules = WarmAlarmStore.loadAll(harness.context)

        assertEquals(setOf(42L), schedules.keys)
        val repaired = JSONArray(harness.lastPersistedJson())
        assertEquals(1, repaired.length())
        assertEquals(42L, repaired.getJSONObject(0).getLong("id"))
    }

    @Test
    fun recurrenceWeekdaysSurviveJsonRoundTrip() {
        val schedule = schedule(id = 42, recurrence = WarmAlarmRecurrenceWire(weekdays = listOf(1, 3, 5)))

        val decoded = WarmAlarmStore.decode(WarmAlarmStore.encode(schedule))

        assertEquals(listOf(1L, 3L, 5L), decoded.recurrence?.weekdays)
    }

    @Test
    fun wakeCheckPromptTextSurvivesJsonRoundTrip() {
        val wakeCheck =
            WarmAlarmWakeCheckWire(
                checkDelayMillis = 60_000,
                retriggerDelayMillis = 120_000,
                maxRetriggers = 2,
                title = "기상 확인",
                body = "일어나셨나요?",
                confirmActionTitle = "일어났어요",
            )

        val decoded = WarmAlarmStore.decode(WarmAlarmStore.encode(schedule(id = 42, wakeCheck = wakeCheck)))

        assertEquals(wakeCheck, decoded.wakeCheck)
    }

    @Test
    fun wakeCheckStoredBeforePromptTextLoadsWithNullText() {
        val stored = WarmAlarmStore.encode(schedule(id = 42))
        stored.put(
            "wakeCheck",
            org.json
                .JSONObject()
                .put("checkDelayMillis", 60_000L)
                .put("maxRetriggers", 1L),
        )

        val decoded = WarmAlarmStore.decode(stored)

        assertEquals(WarmAlarmWakeCheckWire(checkDelayMillis = 60_000, maxRetriggers = 1), decoded.wakeCheck)
    }

    private fun schedule(
        id: Long,
        recurrence: WarmAlarmRecurrenceWire? = null,
        wakeCheck: WarmAlarmWakeCheckWire? = null,
    ) = WarmAlarmScheduleWire(
        id = id,
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
        recurrence = recurrence,
        wakeCheck = wakeCheck,
        androidFullScreenIntent = true,
    )
}

private class StorePreferencesHarness(
    initialJson: String,
) {
    val context: Context = Mockito.mock(Context::class.java)
    private val preferences = Mockito.mock(SharedPreferences::class.java)
    private val editor = Mockito.mock(SharedPreferences.Editor::class.java)

    init {
        Mockito.`when`(context.getSharedPreferences("warm_alarm_store", Context.MODE_PRIVATE)).thenReturn(preferences)
        Mockito.`when`(preferences.getString("schedules", "[]")).thenReturn(initialJson)
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        Mockito.`when`(editor.putString(Mockito.eq("schedules"), Mockito.anyString())).thenReturn(editor)
    }

    fun lastPersistedJson(): String {
        val captor = ArgumentCaptor.forClass(String::class.java)
        Mockito.verify(editor, Mockito.atLeastOnce()).putString(Mockito.eq("schedules"), captor.capture())
        return captor.allValues.last()
    }
}
