package com.andrew.alarm

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal object WarmAlarmStore {
    private const val PREFS = "warm_alarm_store"
    private const val KEY = "schedules"

    fun save(
        context: Context,
        schedule: WarmAlarmScheduleWire,
    ) {
        val all = loadAll(context).toMutableMap()
        all[schedule.id] = schedule
        persist(context, all)
    }

    fun load(
        context: Context,
        id: Long,
    ): WarmAlarmScheduleWire? = loadAll(context)[id]

    fun remove(
        context: Context,
        id: Long,
    ) {
        val all = loadAll(context).toMutableMap()
        all.remove(id)
        persist(context, all)
        prefs(context).edit().remove("retrigger_$id").apply()
    }

    fun getRetriggerCount(
        context: Context,
        id: Long,
    ): Int = prefs(context).getInt("retrigger_$id", 0)

    fun incrementRetriggerCount(
        context: Context,
        id: Long,
    ) {
        val current = getRetriggerCount(context, id)
        prefs(context).edit().putInt("retrigger_$id", current + 1).apply()
    }

    fun reschedule(
        context: Context,
        id: Long,
        scheduledAtMillis: Long,
    ) {
        val existing = loadAll(context).toMutableMap()
        val schedule = existing[id] ?: return
        existing[id] = schedule.copy(scheduledAtMillis = scheduledAtMillis)
        persist(context, existing)
    }

    fun loadAll(context: Context): Map<Long, WarmAlarmScheduleWire> {
        val json = prefs(context).getString(KEY, "[]") ?: "[]"
        val arr = JSONArray(json)
        return buildMap {
            for (i in 0 until arr.length()) {
                val s = decode(arr.getJSONObject(i))
                put(s.id, s)
            }
        }
    }

    fun clear(context: Context) = prefs(context).edit().remove(KEY).apply()

    private fun persist(
        context: Context,
        all: Map<Long, WarmAlarmScheduleWire>,
    ) {
        val arr = JSONArray()
        all.values.forEach { arr.put(encode(it)) }
        prefs(context).edit().putString(KEY, arr.toString()).apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun encode(s: WarmAlarmScheduleWire): JSONObject =
        JSONObject().apply {
            put("id", s.id)
            put("scheduledAtMillis", s.scheduledAtMillis)
            put(
                "notification",
                JSONObject().apply {
                    put("title", s.notification.title)
                    put("body", s.notification.body)
                    s.notification.stopActionTitle?.let { put("stopActionTitle", it) }
                    s.notification.snoozeActionTitle?.let { put("snoozeActionTitle", it) }
                    s.notification.androidIcon?.let { put("androidIcon", it) }
                    s.notification.androidIconColor?.let { put("androidIconColor", it) }
                    put("keepNotificationAfterAlarmEnds", s.notification.keepNotificationAfterAlarmEnds)
                },
            )
            put(
                "audio",
                JSONObject().apply {
                    s.audio.filePath?.let { put("filePath", it) }
                    s.audio.assetPath?.let { put("assetPath", it) }
                    put("loop", s.audio.loop)
                    s.audio.volume?.let { put("volume", it) }
                    s.audio.fadeInDurationMillis?.let { put("fadeInDurationMillis", it) }
                    put("vibrate", s.audio.vibrate)
                    put("volumeEnforced", s.audio.volumeEnforced)
                    s.audio.fadeSteps?.let { steps ->
                        put(
                            "fadeSteps",
                            JSONArray().also { arr ->
                                steps.forEach { step ->
                                    arr.put(
                                        JSONObject().apply {
                                            put("timeMillis", step.timeMillis)
                                            put("volume", step.volume)
                                        },
                                    )
                                }
                            },
                        )
                    }
                },
            )
            s.snooze?.let { put("snooze", JSONObject().apply { put("durationMillis", it.durationMillis) }) }
            s.wakeCheck?.let {
                put(
                    "wakeCheck",
                    JSONObject().apply {
                        put("checkDelayMillis", it.checkDelayMillis)
                        it.retriggerDelayMillis?.let { d -> put("retriggerDelayMillis", d) }
                        it.maxRetriggers?.let { m -> put("maxRetriggers", m) }
                    },
                )
            }
            s.payload?.let { put("payload", it) }
            put("androidFullScreenIntent", s.androidFullScreenIntent)
        }

    private fun decode(obj: JSONObject): WarmAlarmScheduleWire {
        val n = obj.getJSONObject("notification")
        val a = obj.getJSONObject("audio")
        return WarmAlarmScheduleWire(
            id = obj.getLong("id"),
            scheduledAtMillis = obj.getLong("scheduledAtMillis"),
            notification =
                WarmAlarmNotificationWire(
                    title = n.getString("title"),
                    body = n.getString("body"),
                    stopActionTitle = n.optString("stopActionTitle").takeIf { it.isNotEmpty() },
                    snoozeActionTitle = n.optString("snoozeActionTitle").takeIf { it.isNotEmpty() },
                    androidIcon = n.optString("androidIcon").takeIf { it.isNotEmpty() },
                    androidIconColor = if (n.has("androidIconColor")) n.getLong("androidIconColor") else null,
                    keepNotificationAfterAlarmEnds = n.optBoolean("keepNotificationAfterAlarmEnds", false),
                ),
            audio =
                WarmAlarmAudioWire(
                    filePath = a.optString("filePath").takeIf { it.isNotEmpty() },
                    assetPath = a.optString("assetPath").takeIf { it.isNotEmpty() },
                    loop = a.getBoolean("loop"),
                    volume = if (a.has("volume")) a.getDouble("volume") else null,
                    fadeInDurationMillis = if (a.has("fadeInDurationMillis")) a.getLong("fadeInDurationMillis") else null,
                    vibrate = a.getBoolean("vibrate"),
                    volumeEnforced = a.optBoolean("volumeEnforced", false),
                    fadeSteps =
                        if (a.has("fadeSteps")) {
                            val arr = a.getJSONArray("fadeSteps")
                            (0 until arr.length()).map { i ->
                                val fs = arr.getJSONObject(i)
                                WarmAlarmVolumeFadeStepWire(
                                    timeMillis = fs.getLong("timeMillis"),
                                    volume = fs.getDouble("volume"),
                                )
                            }
                        } else {
                            null
                        },
                ),
            snooze =
                if (obj.has("snooze")) {
                    WarmAlarmSnoozeWire(obj.getJSONObject("snooze").getLong("durationMillis"))
                } else {
                    null
                },
            wakeCheck =
                if (obj.has("wakeCheck")) {
                    val w = obj.getJSONObject("wakeCheck")
                    WarmAlarmWakeCheckWire(
                        checkDelayMillis = w.getLong("checkDelayMillis"),
                        retriggerDelayMillis = if (w.has("retriggerDelayMillis")) w.getLong("retriggerDelayMillis") else null,
                        maxRetriggers = if (w.has("maxRetriggers")) w.getLong("maxRetriggers") else null,
                    )
                } else {
                    null
                },
            payload = obj.optString("payload").takeIf { it.isNotEmpty() },
            androidFullScreenIntent = obj.optBoolean("androidFullScreenIntent", true),
        )
    }
}
