package com.andrew.alarm

import android.content.Context
import android.content.SharedPreferences
import android.os.Build

internal interface PendingSnoozeEventPreferences {
    fun read(): Set<String>

    fun write(values: Set<String>): Boolean
}

private class SharedPreferencesPendingSnoozeEventPreferences(
    private val preferences: SharedPreferences,
) : PendingSnoozeEventPreferences {
    override fun read(): Set<String> = preferences.getStringSet(KEY, emptySet())?.toSet().orEmpty()

    override fun write(values: Set<String>): Boolean = preferences.edit().putStringSet(KEY, values).commit()

    private companion object {
        const val KEY = "events"
    }
}

internal data class PendingSnoozeEvent(
    val storageValue: String,
    val event: WarmAlarmEventWire,
)

internal class PendingSnoozeEventStore(
    private val preferences: PendingSnoozeEventPreferences,
) {
    @Synchronized
    fun enqueue(event: WarmAlarmEventWire): Boolean {
        require(event.type == WarmAlarmEventTypeWire.SNOOZED)
        val storageValue = encode(event)
        return preferences.write(preferences.read() + storageValue)
    }

    @Synchronized
    fun loadAll(): List<PendingSnoozeEvent> =
        preferences
            .read()
            .mapNotNull(::decode)
            .sortedWith(compareBy({ it.event.occurredAtMillis }, { it.storageValue }))

    @Synchronized
    fun remove(event: PendingSnoozeEvent): Boolean = preferences.write(preferences.read() - event.storageValue)

    private fun encode(event: WarmAlarmEventWire): String {
        val durationMillis = requireNotNull(event.snoozeDurationMillis)
        val payload = event.payload
        return listOf(
            event.alarmId,
            event.occurredAtMillis,
            durationMillis,
            payload?.length ?: NULL_PAYLOAD_LENGTH,
            payload.orEmpty(),
        ).joinToString(SEPARATOR)
    }

    private fun decode(storageValue: String): PendingSnoozeEvent? {
        val parts = storageValue.split(SEPARATOR, limit = FIELD_COUNT)
        if (parts.size != FIELD_COUNT) return null
        val alarmId = parts[0].toLongOrNull() ?: return null
        val occurredAtMillis = parts[1].toLongOrNull() ?: return null
        val durationMillis = parts[2].toLongOrNull() ?: return null
        val payloadLength = parts[3].toIntOrNull() ?: return null
        val payload = parts[4]
        if (payloadLength != NULL_PAYLOAD_LENGTH && payload.length != payloadLength) return null
        return PendingSnoozeEvent(
            storageValue = storageValue,
            event =
                WarmAlarmEventWire(
                    alarmId = alarmId,
                    type = WarmAlarmEventTypeWire.SNOOZED,
                    occurredAtMillis = occurredAtMillis,
                    snoozeDurationMillis = durationMillis,
                    payload = payload.takeUnless { payloadLength == NULL_PAYLOAD_LENGTH },
                ),
        )
    }

    companion object {
        private const val PREFERENCES_NAME = "warm_alarm_pending_snooze_events"
        private const val SEPARATOR = "|"
        private const val FIELD_COUNT = 5
        private const val NULL_PAYLOAD_LENGTH = -1

        fun create(context: Context): PendingSnoozeEventStore {
            val storageContext =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.createDeviceProtectedStorageContext()
                } else {
                    context
                }
            val preferences = storageContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            return PendingSnoozeEventStore(SharedPreferencesPendingSnoozeEventPreferences(preferences))
        }
    }
}

internal class PendingSnoozeEventReplay(
    private val store: PendingSnoozeEventStore,
    private val emit: (WarmAlarmEventWire, (Result<Unit>) -> Unit) -> Unit,
) {
    var isDraining = false
        private set

    fun drain() {
        if (isDraining) return
        isDraining = true
        emitNext()
    }

    private fun emitNext() {
        val pending = store.loadAll().firstOrNull()
        if (pending == null) {
            isDraining = false
            return
        }
        emit(pending.event) { result ->
            if (result.isFailure || !store.remove(pending)) {
                isDraining = false
                return@emit
            }
            emitNext()
        }
    }
}
