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

    private fun schedule(
        id: Long,
        recurrence: WarmAlarmRecurrenceWire? = null,
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
