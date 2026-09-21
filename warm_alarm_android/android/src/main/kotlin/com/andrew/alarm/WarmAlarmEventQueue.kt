package com.andrew.alarm

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal interface WarmAlarmEventQueueStorage {
    fun read(): String?

    fun write(value: String): Boolean
}

private class SharedPreferencesWarmAlarmEventQueueStorage(
    private val preferences: SharedPreferences,
) : WarmAlarmEventQueueStorage {
    override fun read(): String? = preferences.getString(KEY, null)

    override fun write(value: String): Boolean = preferences.edit().putString(KEY, value).commit()

    private companion object {
        const val KEY = "queue_v1"
    }
}

internal data class QueuedWarmAlarmEvent(
    val occurrenceId: String,
    val event: WarmAlarmEventWire,
)

internal interface WarmAlarmEventQueueStoreProtocol {
    fun enqueue(event: WarmAlarmEventWire): Boolean

    fun peek(): QueuedWarmAlarmEvent?

    fun remove(occurrenceId: String): Boolean
}

/**
 * A persistent FIFO. When [capacity] is reached, enqueue drops the oldest occurrence.
 */
internal class WarmAlarmEventQueueStore(
    private val storage: WarmAlarmEventQueueStorage,
    private val capacity: Int = DEFAULT_CAPACITY,
    private val occurrenceId: () -> String = { UUID.randomUUID().toString() },
) : WarmAlarmEventQueueStoreProtocol {
    init {
        require(capacity > 0)
    }

    override fun enqueue(event: WarmAlarmEventWire): Boolean =
        synchronized(storageLock) {
            val events = readAndRepair().toMutableList()
            events += QueuedWarmAlarmEvent(occurrenceId(), event)
            while (events.size > capacity) {
                events.removeAt(0)
            }
            persist(events)
        }

    fun loadAll(): List<QueuedWarmAlarmEvent> = synchronized(storageLock) { readAndRepair() }

    override fun peek(): QueuedWarmAlarmEvent? = synchronized(storageLock) { readAndRepair().firstOrNull() }

    override fun remove(occurrenceId: String): Boolean =
        synchronized(storageLock) {
            val events = readAndRepair()
            val retained = events.filterNot { it.occurrenceId == occurrenceId }
            if (retained.size == events.size) return@synchronized true
            persist(retained)
        }

    private fun readAndRepair(): List<QueuedWarmAlarmEvent> {
        val raw = storage.read() ?: return emptyList()
        val root = runCatching { JSONObject(raw) }.getOrNull()
        if (root == null || root.optInt("version", -1) != STORAGE_VERSION || root.optJSONArray("events") == null) {
            persist(emptyList())
            return emptyList()
        }
        val array = root.getJSONArray("events")
        val valid =
            buildList {
                for (index in 0 until array.length()) {
                    runCatching { decode(array.optJSONObject(index)) }.getOrNull()?.let(::add)
                }
            }
        if (valid.size != array.length()) {
            persist(valid)
        }
        return valid
    }

    private fun persist(events: List<QueuedWarmAlarmEvent>): Boolean {
        val encoded = JSONArray()
        events.forEach { encoded.put(encode(it)) }
        return storage.write(
            JSONObject()
                .put("version", STORAGE_VERSION)
                .put("events", encoded)
                .toString(),
        )
    }

    private fun encode(queued: QueuedWarmAlarmEvent): JSONObject =
        JSONObject()
            .put("occurrenceId", queued.occurrenceId)
            .put("alarmId", queued.event.alarmId)
            .put(
                "type",
                queued.event.type.name
                    .lowercase(),
            ).put("occurredAtMillis", queued.event.occurredAtMillis)
            .putNullable("snoozeDurationMillis", queued.event.snoozeDurationMillis)
            .putNullable("payload", queued.event.payload)
            .putNullable(
                "failureCode",
                queued.event.failure
                    ?.code
                    ?.raw,
            ).putNullable("failureMessage", queued.event.failure?.message)

    private fun decode(value: JSONObject?): QueuedWarmAlarmEvent? {
        value ?: return null
        val occurrenceId = value.optString("occurrenceId").takeIf { it.isNotEmpty() } ?: return null
        if (!value.has("alarmId") || !value.has("occurredAtMillis")) return null
        val type =
            runCatching { WarmAlarmEventTypeWire.valueOf(value.optString("type").uppercase()) }
                .getOrNull() ?: return null
        val failure =
            if (value.isNull("failureCode")) {
                null
            } else {
                val code = WarmAlarmFailureCodeWire.ofRaw(value.optInt("failureCode", -1)) ?: return null
                WarmAlarmFailureWire(code = code, message = value.optNullableString("failureMessage"))
            }
        return QueuedWarmAlarmEvent(
            occurrenceId = occurrenceId,
            event =
                WarmAlarmEventWire(
                    alarmId = value.getLong("alarmId"),
                    type = type,
                    occurredAtMillis = value.getLong("occurredAtMillis"),
                    snoozeDurationMillis = value.optNullableLong("snoozeDurationMillis"),
                    failure = failure,
                    payload = value.optNullableString("payload"),
                ),
        )
    }

    companion object {
        const val DEFAULT_CAPACITY = 64
        private const val STORAGE_VERSION = 1
        private const val PREFERENCES_NAME = "warm_alarm_event_queue"
        private val storageLock = Any()

        fun create(context: Context): WarmAlarmEventQueueStore {
            val storageContext =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.createDeviceProtectedStorageContext()
                } else {
                    context
                }
            val preferences = storageContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            return WarmAlarmEventQueueStore(SharedPreferencesWarmAlarmEventQueueStorage(preferences))
        }
    }
}

internal class WarmAlarmEventQueue(
    private val store: WarmAlarmEventQueueStoreProtocol,
    private val emit: (WarmAlarmEventWire, (Result<Unit>) -> Unit) -> Unit,
) {
    private var isDraining = false
    private var drainRequestedWhileActive = false

    fun enqueue(event: WarmAlarmEventWire): Boolean {
        if (!store.enqueue(event)) return false
        drain()
        return true
    }

    fun drain() {
        val shouldStart =
            synchronized(this) {
                if (isDraining) {
                    drainRequestedWhileActive = true
                    return@synchronized false
                }
                isDraining = true
                true
            }
        if (!shouldStart) return
        emitNext()
    }

    private fun emitNext() {
        val pending =
            synchronized(this) {
                drainRequestedWhileActive = false
                store.peek() ?: run {
                    isDraining = false
                    return@synchronized null
                }
            } ?: return
        emit(pending.event) { result ->
            if (result.isFailure || !store.remove(pending.occurrenceId)) {
                retryRequestedDrainOrStop()
                return@emit
            }
            emitNext()
        }
    }

    private fun retryRequestedDrainOrStop() {
        val shouldRetry =
            synchronized(this) {
                if (!drainRequestedWhileActive) {
                    isDraining = false
                    return@synchronized false
                }
                drainRequestedWhileActive = false
                true
            }
        if (shouldRetry) emitNext()
    }
}

internal fun migratePendingSnoozeEvents(
    legacyStore: PendingSnoozeEventStore,
    queueStore: WarmAlarmEventQueueStore,
): Boolean {
    for (pending in legacyStore.loadAll()) {
        if (!queueStore.enqueue(pending.event)) return false
        if (!legacyStore.remove(pending)) return false
    }
    return true
}

private fun JSONObject.putNullable(
    key: String,
    value: Any?,
): JSONObject = put(key, value ?: JSONObject.NULL)

private fun JSONObject.optNullableString(key: String): String? = if (isNull(key)) null else optString(key).takeIf { has(key) }

private fun JSONObject.optNullableLong(key: String): Long? =
    if (isNull(key) || !has(key)) null else runCatching { getLong(key) }.getOrNull()
