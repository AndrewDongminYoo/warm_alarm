package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmEventQueueTest {
    @Test
    fun storePreservesFifoAndDuplicateOccurrencesAcrossRecreation() {
        val storage = FakeEventQueueStorage()
        val ids = ArrayDeque(listOf("occurrence-1", "occurrence-2"))
        val event = event(alarmId = 42)

        WarmAlarmEventQueueStore(storage, occurrenceId = ids::removeFirst).apply {
            enqueue(event)
            enqueue(event)
        }

        val restored = WarmAlarmEventQueueStore(storage).loadAll()
        assertEquals(listOf("occurrence-1", "occurrence-2"), restored.map { it.occurrenceId })
        assertEquals(listOf(event, event), restored.map { it.event })
    }

    @Test
    fun storeDropsOldestOccurrenceAtCapacity() {
        val storage = FakeEventQueueStorage()
        val ids = ArrayDeque(listOf("1", "2", "3"))
        val store = WarmAlarmEventQueueStore(storage, capacity = 2, occurrenceId = ids::removeFirst)

        store.enqueue(event(alarmId = 1))
        store.enqueue(event(alarmId = 2))
        store.enqueue(event(alarmId = 3))

        assertEquals(listOf(2L, 3L), store.loadAll().map { it.event.alarmId })
    }

    @Test
    fun storeRepairsCorruptRootAndCorruptRecords() {
        val corruptRoot = FakeEventQueueStorage("not-json")
        assertTrue(WarmAlarmEventQueueStore(corruptRoot).loadAll().isEmpty())
        assertEquals("{\"version\":1,\"events\":[]}", corruptRoot.value)

        val oneCorruptRecord =
            FakeEventQueueStorage(
                """{"version":1,"events":[{"occurrenceId":"bad"},{"occurrenceId":"good","alarmId":7,"type":"fired","occurredAtMillis":1000}]}""",
            )
        val loaded = WarmAlarmEventQueueStore(oneCorruptRecord).loadAll()
        assertEquals(listOf("good"), loaded.map { it.occurrenceId })
        assertEquals(listOf(7L), loaded.map { it.event.alarmId })
        assertFalse(oneCorruptRecord.value.orEmpty().contains("bad"))
    }

    @Test
    fun storeDropsMalformedScalarRecordAndPreservesValidNeighbors() {
        val storage =
            FakeEventQueueStorage(
                """{"version":1,"events":[{"occurrenceId":"first","alarmId":1,"type":"fired","occurredAtMillis":1000},{"occurrenceId":"bad","alarmId":"oops","type":"fired","occurredAtMillis":1000},{"occurrenceId":"last","alarmId":3,"type":"stopped","occurredAtMillis":1000}]}""",
            )

        val loaded = WarmAlarmEventQueueStore(storage).loadAll()

        assertEquals(listOf("first", "last"), loaded.map { it.occurrenceId })
        assertEquals(listOf(1L, 3L), loaded.map { it.event.alarmId })
        assertFalse(storage.value.orEmpty().contains("bad"))
    }

    @Test
    fun drainRemovesOnlySuccessfulHeadAndRetriesFailureOnNextEnqueue() {
        val store = WarmAlarmEventQueueStore(FakeEventQueueStorage(), occurrenceId = { "id-${nextId++}" })
        val callbacks = ArrayDeque<(Result<Unit>) -> Unit>()
        val emitted = mutableListOf<Long>()
        val queue =
            WarmAlarmEventQueue(store) { event, callback ->
                emitted += event.alarmId
                callbacks += callback
            }

        assertTrue(queue.enqueue(event(alarmId = 1)))
        assertTrue(queue.enqueue(event(alarmId = 2)))
        assertEquals(listOf(1L), emitted)

        callbacks.removeFirst()(Result.failure(IllegalStateException("Dart unavailable")))
        assertEquals(listOf(1L, 2L), store.loadAll().map { it.event.alarmId })

        assertTrue(queue.enqueue(event(alarmId = 3)))
        assertEquals(listOf(1L, 1L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 1L, 2L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 1L, 2L, 3L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun successfulAckContinuesAfterCapacityEvictsTheInFlightHead() {
        val store = WarmAlarmEventQueueStore(FakeEventQueueStorage(), capacity = 2)
        val callbacks = ArrayDeque<(Result<Unit>) -> Unit>()
        val emitted = mutableListOf<Long>()
        val queue =
            WarmAlarmEventQueue(store) { event, callback ->
                emitted += event.alarmId
                callbacks += callback
            }

        queue.enqueue(event(alarmId = 1))
        queue.enqueue(event(alarmId = 2))
        queue.enqueue(event(alarmId = 3))
        assertEquals(listOf(2L, 3L), store.loadAll().map { it.event.alarmId })

        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 2L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 2L, 3L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun migrationCopiesLegacySnoozesBeforeRemovingThem() {
        val legacyPreferences = FakeStringSetPreferencesForMigration()
        val legacy = PendingSnoozeEventStore(legacyPreferences)
        val first = event(alarmId = 1, type = WarmAlarmEventTypeWire.SNOOZED, snoozeDurationMillis = 60_000)
        val second = event(alarmId = 2, type = WarmAlarmEventTypeWire.SNOOZED, snoozeDurationMillis = 60_000)
        legacy.enqueue(first)
        legacy.enqueue(second)
        val queueStore = WarmAlarmEventQueueStore(FakeEventQueueStorage())

        assertTrue(migratePendingSnoozeEvents(legacy, queueStore))

        assertEquals(listOf(first, second), queueStore.loadAll().map { it.event }.sortedBy { it.alarmId })
        assertTrue(legacy.loadAll().isEmpty())
    }

    @Test
    fun migrationKeepsLegacySnoozeWhenTheNewQueueWriteFails() {
        val legacy = PendingSnoozeEventStore(FakeStringSetPreferencesForMigration())
        val event = event(alarmId = 1, type = WarmAlarmEventTypeWire.SNOOZED, snoozeDurationMillis = 60_000)
        legacy.enqueue(event)

        assertFalse(migratePendingSnoozeEvents(legacy, WarmAlarmEventQueueStore(FakeEventQueueStorage(writeSucceeds = false))))

        assertEquals(listOf(event), legacy.loadAll().map { it.event })
    }

    private fun event(
        alarmId: Long,
        type: WarmAlarmEventTypeWire = WarmAlarmEventTypeWire.FIRED,
        snoozeDurationMillis: Long? = null,
    ) = WarmAlarmEventWire(
        alarmId = alarmId,
        type = type,
        occurredAtMillis = 1_000,
        snoozeDurationMillis = snoozeDurationMillis,
        payload = "payload",
    )

    private companion object {
        var nextId = 0
    }
}

private class FakeEventQueueStorage(
    initialValue: String? = null,
    private val writeSucceeds: Boolean = true,
) : WarmAlarmEventQueueStorage {
    var value = initialValue

    override fun read(): String? = value

    override fun write(value: String): Boolean {
        if (!writeSucceeds) return false
        this.value = value
        return true
    }
}

private class FakeStringSetPreferencesForMigration : PendingSnoozeEventPreferences {
    private var values = emptySet<String>()

    override fun read(): Set<String> = values

    override fun write(values: Set<String>): Boolean {
        this.values = values.toSet()
        return true
    }
}
