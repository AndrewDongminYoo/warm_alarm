package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import org.mockito.Mockito
import java.lang.reflect.Field
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WarmAlarmSchedulingTest {
    @Test
    fun initialSchedulingUsesLegacyExactOnApi19() = assertScheduling(SchedulingEntry.INITIAL, 19, "setExact")

    @Test
    fun initialSchedulingUsesLegacyExactOnApi22() = assertScheduling(SchedulingEntry.INITIAL, 22, "setExact")

    @Test
    fun initializationUsesLegacyExactOnApi19() = assertScheduling(SchedulingEntry.INITIALIZE, 19, "setExact")

    @Test
    fun initializationUsesLegacyExactOnApi22() = assertScheduling(SchedulingEntry.INITIALIZE, 22, "setExact")

    @Test
    fun bootRecoveryUsesLegacyExactOnApi19() = assertScheduling(SchedulingEntry.BOOT, 19, "setExact")

    @Test
    fun bootRecoveryUsesLegacyExactOnApi22() = assertScheduling(SchedulingEntry.BOOT, 22, "setExact")

    @Test
    fun initialSchedulingKeepsModernExactAndInexactBehavior() = assertModernScheduling(SchedulingEntry.INITIAL)

    @Test
    fun initializationKeepsModernExactAndInexactBehavior() = assertModernScheduling(SchedulingEntry.INITIALIZE)

    @Test
    fun bootRecoveryKeepsModernExactAndInexactBehavior() = assertModernScheduling(SchedulingEntry.BOOT)

    @Test
    fun legacyRecoveryPreservesTheActiveSnoozeDeadline() {
        for (sdkInt in listOf(19, 22)) {
            for (entry in listOf(SchedulingEntry.INITIALIZE, SchedulingEntry.BOOT)) {
                assertScheduling(entry, sdkInt, "setExact", recoveringSnooze = true)
            }
        }
    }

    @Test
    fun lockedBootRecoveryKeepsTheInexactFallback() {
        assertScheduling(SchedulingEntry.LOCKED_BOOT, 31, "setAndAllowWhileIdle", exactGranted = false)
    }

    private fun assertModernScheduling(entry: SchedulingEntry) {
        assertScheduling(entry, 23, "setExactAndAllowWhileIdle")
        assertScheduling(entry, 31, "setExactAndAllowWhileIdle")
        assertScheduling(entry, 31, "setAndAllowWhileIdle", exactGranted = false)
    }

    private fun assertScheduling(
        entry: SchedulingEntry,
        sdkInt: Int,
        expectedMethod: String,
        exactGranted: Boolean = true,
        recoveringSnooze: Boolean = false,
    ) {
        SchedulingHarness(sdkInt, exactGranted).use { harness ->
            val scheduledAt = System.currentTimeMillis() + 60_000
            val fireAt = if (recoveringSnooze) scheduledAt + 120_000 else scheduledAt
            val schedule =
                WarmAlarmScheduleWire(
                    id = 41,
                    scheduledAtMillis = scheduledAt,
                    notification = WarmAlarmNotificationWire(title = "Alarm", body = "Schedule", keepNotificationAfterAlarmEnds = false),
                    audio = WarmAlarmAudioWire(loop = true, vibrate = false, volumeEnforced = false),
                    androidFullScreenIntent = false,
                )
            if (entry != SchedulingEntry.INITIAL) {
                WarmAlarmStore.save(harness.context, schedule)
                if (recoveringSnooze) {
                    WarmAlarmStore.setActiveSnooze(harness.context, schedule.id, fireAt)
                    assertEquals(fireAt, WarmAlarmStore.activeSnoozeUntilMillis(harness.context, schedule.id))
                }
            }

            when (entry) {
                SchedulingEntry.INITIAL -> {
                    var result: WarmAlarmScheduleResultWire? = null
                    harness.plugin().scheduleAlarm(schedule) { result = it.getOrThrow() }
                    val completed = assertNotNull(result)
                    assertEquals(41L, completed.alarmId)
                    if (!exactGranted) {
                        assertEquals(WarmAlarmReadinessLevelWire.LIMITED, completed.readiness.level)
                        assertTrue(WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED in completed.readiness.reasons)
                        assertNotNull(completed.warning)
                    } else {
                        assertEquals(WarmAlarmReadinessLevelWire.READY, completed.readiness.level)
                        assertNull(completed.warning)
                    }
                    val event =
                        WarmAlarmEventQueueStore
                            .create(harness.context)
                            .loadAll()
                            .single()
                            .event
                    assertEquals(41L, event.alarmId)
                    assertEquals(WarmAlarmEventTypeWire.SCHEDULED, event.type)
                }

                SchedulingEntry.INITIALIZE -> {
                    var completed = false
                    harness.plugin().initialize {
                        it.getOrThrow()
                        completed = true
                    }
                    assertTrue(completed)
                }

                SchedulingEntry.BOOT, SchedulingEntry.LOCKED_BOOT -> {
                    val intent = Mockito.mock(Intent::class.java)
                    Mockito.`when`(intent.action).thenReturn(
                        if (entry == SchedulingEntry.BOOT) Intent.ACTION_BOOT_COMPLETED else "android.intent.action.LOCKED_BOOT_COMPLETED",
                    )
                    WarmAlarmBootReceiver().onReceive(harness.context, intent)
                }
            }

            assertEquals(
                listOf(ScheduledAlarmCall(expectedMethod, AlarmManager.RTC_WAKEUP, fireAt, harness.pendingIntent)),
                harness.calls,
                "$entry on API $sdkInt",
            )
            assertEquals(listOf(41), harness.scheduledRequestCodes)
            assertEquals(scheduledAt, WarmAlarmStore.load(harness.context, 41)?.scheduledAtMillis)
            if (recoveringSnooze) assertEquals(fireAt, WarmAlarmStore.activeSnoozeUntilMillis(harness.context, 41))
        }
    }
}

private enum class SchedulingEntry { INITIAL, INITIALIZE, BOOT, LOCKED_BOOT }

private data class ScheduledAlarmCall(
    val method: String,
    val type: Int,
    val fireAt: Long,
    val pendingIntent: PendingIntent,
)

private class SchedulingHarness(
    sdkInt: Int,
    exactGranted: Boolean,
) : AutoCloseable {
    val context = Mockito.mock(Context::class.java)
    val pendingIntent = Mockito.mock(PendingIntent::class.java)
    val calls = mutableListOf<ScheduledAlarmCall>()
    val scheduledRequestCodes = mutableListOf<Int>()
    private val resources = mutableListOf<AutoCloseable>()
    private val alarmManager =
        Mockito.mock(AlarmManager::class.java) { call ->
            when (call.method.name) {
                "setExact", "setExactAndAllowWhileIdle", "setAndAllowWhileIdle" -> {
                    calls += ScheduledAlarmCall(call.method.name, call.getArgument(0), call.getArgument(1), call.getArgument(2))
                    null
                }

                "canScheduleExactAlarms" -> {
                    check(sdkInt >= 31) { "Exact-alarm permission API is unavailable on API $sdkInt" }
                    exactGranted
                }

                else -> {
                    Mockito.RETURNS_DEFAULTS.answer(call)
                }
            }
        }

    init {
        resources += AndroidSdkOverride(sdkInt)
        Mockito.`when`(context.packageName).thenReturn("com.andrew.alarm")
        Mockito.`when`(context.getSystemService(Context.ALARM_SERVICE)).thenReturn(alarmManager)
        Mockito.`when`(context.getSystemService(Context.NOTIFICATION_SERVICE)).thenReturn(Mockito.mock(NotificationManager::class.java))
        Mockito.`when`(context.createDeviceProtectedStorageContext()).thenReturn(context)
        val preferencesByName = mutableMapOf<String, SharedPreferences>()
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt())).thenAnswer {
            preferencesByName.getOrPut(it.getArgument(0)) { inMemoryPreferences() }
        }
        resources += Mockito.mockConstruction(Intent::class.java)
        resources += Mockito.mockStatic(android.net.Uri::class.java)
        val pending = Mockito.mockStatic(PendingIntent::class.java)
        pending
            .`when`<PendingIntent> {
                PendingIntent.getBroadcast(
                    Mockito.any(Context::class.java),
                    Mockito.anyInt(),
                    Mockito.any(Intent::class.java),
                    Mockito.anyInt(),
                )
            }.thenAnswer {
                if (it.getArgument<Int>(3) and PendingIntent.FLAG_NO_CREATE != 0) {
                    null
                } else {
                    scheduledRequestCodes += it.getArgument<Int>(1)
                    pendingIntent
                }
            }
        resources += pending
        val notifications = Mockito.mock(NotificationManagerCompat::class.java)
        Mockito.`when`(notifications.areNotificationsEnabled()).thenReturn(true)
        val notificationFactory = Mockito.mockStatic(NotificationManagerCompat::class.java)
        notificationFactory.`when`<NotificationManagerCompat> { NotificationManagerCompat.from(context) }.thenReturn(notifications)
        resources += notificationFactory
    }

    fun plugin(): WarmAlarmPlugin {
        val plugin = Mockito.mock(WarmAlarmPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        for ((name, value) in mapOf(
            "context" to context,
            "alarmManager" to alarmManager,
            "eventQueue" to WarmAlarmEventQueue(WarmAlarmEventQueueStore.create(context)) { _, _ -> },
        )) {
            WarmAlarmPlugin::class.java
                .getDeclaredField(name)
                .apply { isAccessible = true }
                .set(plugin, value)
        }
        return plugin
    }

    private fun inMemoryPreferences(): SharedPreferences {
        val values = mutableMapOf<String, Any>()
        val preferences = Mockito.mock(SharedPreferences::class.java)
        val editor = Mockito.mock(SharedPreferences.Editor::class.java, Mockito.RETURNS_SELF)
        Mockito.`when`(preferences.contains(Mockito.anyString())).thenAnswer { it.getArgument<String>(0) in values }
        Mockito.`when`(preferences.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            values[it.getArgument<String>(0)] as String? ?: it.getArgument<String?>(1)
        }
        Mockito.`when`(preferences.getLong(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
            values[it.getArgument<String>(0)] as Long? ?: it.getArgument<Long>(1)
        }
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        Mockito.`when`(editor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<String>(1)
            editor
        }
        Mockito.`when`(editor.putLong(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<Long>(1)
            editor
        }
        Mockito.`when`(editor.remove(Mockito.anyString())).thenAnswer {
            values.remove(it.getArgument<String>(0))
            editor
        }
        Mockito.`when`(editor.commit()).thenReturn(true)
        return preferences
    }

    override fun close() {
        resources.asReversed().forEach { it.close() }
    }
}

/** The JVM Android stub has no runtime SDK; scope its static value to each test fixture. */
private class AndroidSdkOverride(
    sdkInt: Int,
) : AutoCloseable {
    private val field = Build.VERSION::class.java.getDeclaredField("SDK_INT")
    private val original = field.getInt(null)
    private val unsafeClass = Class.forName("sun.misc.Unsafe")
    private val unsafe =
        unsafeClass
            .getDeclaredField("theUnsafe")
            .apply { isAccessible = true }
            .get(null)
    private val base = unsafeClass.getMethod("staticFieldBase", Field::class.java).invoke(unsafe, field)
    private val offset = unsafeClass.getMethod("staticFieldOffset", Field::class.java).invoke(unsafe, field)
    private val putInt =
        unsafeClass.getMethod(
            "putIntVolatile",
            Any::class.java,
            Long::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
        )

    init {
        putInt.invoke(unsafe, base, offset, sdkInt)
        check(Build.VERSION.SDK_INT == sdkInt)
    }

    override fun close() {
        putInt.invoke(unsafe, base, offset, original)
    }
}
