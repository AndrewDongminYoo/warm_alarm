package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PendingSnoozeEventStoreTest {
    @Test
    fun queuedEventSurvivesStoreRecreation() {
        val preferences = FakeStringSetPreferences()
        val event = snoozedEvent(occurredAtMillis = 1_000, payload = "alarm|payload")

        PendingSnoozeEventStore(preferences).enqueue(event)

        assertEquals(listOf(event), PendingSnoozeEventStore(preferences).loadAll().map { it.event })
    }

    @Test
    fun successfulReplayRemovesEvent() {
        val preferences = FakeStringSetPreferences()
        val store = PendingSnoozeEventStore(preferences)
        val event = snoozedEvent(occurredAtMillis = 1_000)
        store.enqueue(event)
        val emitted = mutableListOf<WarmAlarmEventWire>()
        val replay =
            PendingSnoozeEventReplay(store) { queuedEvent, callback ->
                emitted += queuedEvent
                callback(Result.success(Unit))
            }

        replay.drain()

        assertEquals(listOf(event), emitted)
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun failedReplayKeepsEventForNextEngineAttachment() {
        val preferences = FakeStringSetPreferences()
        val store = PendingSnoozeEventStore(preferences)
        val event = snoozedEvent(occurredAtMillis = 1_000)
        store.enqueue(event)
        val replay =
            PendingSnoozeEventReplay(store) { _, callback ->
                callback(Result.failure(IllegalStateException("engine detached")))
            }

        replay.drain()

        assertEquals(listOf(event), store.loadAll().map { it.event })
        assertFalse(replay.isDraining)
    }

    @Test
    fun replayPreservesSnoozeOrder() {
        val preferences = FakeStringSetPreferences()
        val store = PendingSnoozeEventStore(preferences)
        val later = snoozedEvent(occurredAtMillis = 2_000)
        val earlier = snoozedEvent(occurredAtMillis = 1_000)
        store.enqueue(later)
        store.enqueue(earlier)
        val emitted = mutableListOf<WarmAlarmEventWire>()
        val replay =
            PendingSnoozeEventReplay(store) { event, callback ->
                emitted += event
                callback(Result.success(Unit))
            }

        replay.drain()

        assertEquals(listOf(earlier, later), emitted)
    }

    @Test
    fun queueRejectsNonSnoozeEvents() {
        val store = PendingSnoozeEventStore(FakeStringSetPreferences())

        assertFailsWith<IllegalArgumentException> {
            store.enqueue(
                WarmAlarmEventWire(
                    alarmId = 42,
                    type = WarmAlarmEventTypeWire.STOPPED,
                    occurredAtMillis = 1_000,
                ),
            )
        }
    }

    @Test
    fun enqueueReportsFailedPersistence() {
        val preferences = FakeStringSetPreferences(writeSucceeds = false)
        val store = PendingSnoozeEventStore(preferences)

        assertFalse(store.enqueue(snoozedEvent(occurredAtMillis = 1_000)))
        assertTrue(store.loadAll().isEmpty())
    }

    private fun snoozedEvent(
        occurredAtMillis: Long,
        payload: String? = null,
    ) = WarmAlarmEventWire(
        alarmId = 42,
        type = WarmAlarmEventTypeWire.SNOOZED,
        occurredAtMillis = occurredAtMillis,
        snoozeDurationMillis = 300_000,
        payload = payload,
    )
}

private class FakeStringSetPreferences(
    private val writeSucceeds: Boolean = true,
) : PendingSnoozeEventPreferences {
    private var values = emptySet<String>()

    override fun read(): Set<String> = values

    override fun write(values: Set<String>): Boolean {
        if (!writeSucceeds) return false
        this.values = values.toSet()
        return true
    }
}
