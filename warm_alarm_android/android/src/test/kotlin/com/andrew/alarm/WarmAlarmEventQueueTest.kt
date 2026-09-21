package com.andrew.alarm

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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
        assertEquals(listOf(1L), emitted)

        callbacks.removeFirst()(Result.failure(IllegalStateException("Dart unavailable")))
        assertEquals(listOf(1L), store.loadAll().map { it.event.alarmId })

        assertTrue(queue.enqueue(event(alarmId = 2)))
        assertEquals(listOf(1L, 1L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 1L, 2L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun failedCallbackConsumesOneConcurrentDrainRequestWithoutLooping() {
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

        callbacks.removeFirst()(Result.failure(IllegalStateException("Dart unavailable")))
        assertEquals(listOf(1L, 1L), emitted)

        callbacks.removeFirst()(Result.failure(IllegalStateException("still unavailable")))
        assertEquals(listOf(1L, 1L), emitted)

        queue.drain()
        assertEquals(listOf(1L, 1L, 1L), emitted)
    }

    @Test
    fun failedRemovalConsumesOneConcurrentDrainRequest() {
        val storage = FakeEventQueueStorage()
        val store = WarmAlarmEventQueueStore(storage, occurrenceId = { "id-${nextId++}" })
        val callbacks = ArrayDeque<(Result<Unit>) -> Unit>()
        val emitted = mutableListOf<Long>()
        val queue =
            WarmAlarmEventQueue(store) { event, callback ->
                emitted += event.alarmId
                callbacks += callback
            }

        assertTrue(queue.enqueue(event(alarmId = 1)))
        assertTrue(queue.enqueue(event(alarmId = 2)))
        storage.writeSucceeds = false

        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 1L), emitted)
        assertEquals(listOf(1L, 2L), store.loadAll().map { it.event.alarmId })

        storage.writeSucceeds = true
        callbacks.removeFirst()(Result.success(Unit))
        assertEquals(listOf(1L, 1L, 2L), emitted)
        callbacks.removeFirst()(Result.success(Unit))
        assertTrue(store.loadAll().isEmpty())
    }

    @Test
    fun successfulAckDoesNotLoseEnqueueDuringTheFollowUpEmptyCheck() {
        val first = event(alarmId = 1)
        val second = event(alarmId = 2)
        val store = CoordinatedWarmAlarmEventQueueStore(first, second)
        val callbacks = ArrayDeque<(Result<Unit>) -> Unit>()
        val emitted = mutableListOf<Long>()
        val queue =
            WarmAlarmEventQueue(store) { event, callback ->
                emitted += event.alarmId
                callbacks += callback
            }
        store.coordinateNextEmptyPeek(queue)

        queue.drain()
        callbacks.removeFirst()(Result.success(Unit))
        store.awaitConcurrentDrain()

        assertEquals(listOf(1L, 2L), emitted)
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

private class CoordinatedWarmAlarmEventQueueStore(
    first: WarmAlarmEventWire,
    private val second: WarmAlarmEventWire,
) : WarmAlarmEventQueueStoreProtocol {
    private val records = mutableListOf(QueuedWarmAlarmEvent("first", first))
    private val drainAttempted = CountDownLatch(1)
    private val drainReturned = CountDownLatch(1)
    private val workerFinished = CountDownLatch(1)
    private var coordinateNextEmptyPeek = false
    private lateinit var queue: WarmAlarmEventQueue

    fun coordinateNextEmptyPeek(queue: WarmAlarmEventQueue) {
        this.queue = queue
        coordinateNextEmptyPeek = true
    }

    override fun enqueue(event: WarmAlarmEventWire): Boolean {
        synchronized(records) {
            records += QueuedWarmAlarmEvent("second", event)
        }
        return true
    }

    override fun peek(): QueuedWarmAlarmEvent? {
        val shouldCoordinate =
            synchronized(records) {
                if (records.isNotEmpty() || !coordinateNextEmptyPeek) return records.firstOrNull()
                coordinateNextEmptyPeek = false
                true
            }
        if (shouldCoordinate) {
            Thread {
                enqueue(second)
                drainAttempted.countDown()
                queue.drain()
                drainReturned.countDown()
                workerFinished.countDown()
            }.start()
            check(drainAttempted.await(1, TimeUnit.SECONDS))
            drainReturned.await(250, TimeUnit.MILLISECONDS)
        }
        return null
    }

    override fun remove(occurrenceId: String): Boolean {
        synchronized(records) {
            records.removeAll { it.occurrenceId == occurrenceId }
        }
        return true
    }

    fun awaitConcurrentDrain() {
        check(workerFinished.await(1, TimeUnit.SECONDS))
    }
}

private class FakeEventQueueStorage(
    initialValue: String? = null,
    var writeSucceeds: Boolean = true,
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
