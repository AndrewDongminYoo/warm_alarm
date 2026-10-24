package com.andrew.alarm

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertSame

class WarmAlarmPluginTest {
    @Test
    fun invalidScheduleAndCancellationFailBeforeTouchingAndroid() {
        val ids = listOf(Int.MIN_VALUE.toLong() - 1, Int.MAX_VALUE.toLong() + 1, 4_294_967_296L, Long.MIN_VALUE, Long.MAX_VALUE)
        for (id in ids) {
            val context = Mockito.mock(Context::class.java) { throw AssertionError("Invalid ID reached Android: ${it.method.name}") }
            val plugin = Mockito.mock(WarmAlarmPlugin::class.java, Mockito.CALLS_REAL_METHODS)
            setPrivateField(plugin, "context", context)
            val schedule =
                WarmAlarmScheduleWire(
                    id = id,
                    scheduledAtMillis = 1_234,
                    notification = WarmAlarmNotificationWire(title = "Alarm", body = "ID", keepNotificationAfterAlarmEnds = false),
                    audio = WarmAlarmAudioWire(loop = true, vibrate = false, volumeEnforced = false),
                    androidFullScreenIntent = false,
                )
            var scheduleError: Throwable? = null
            plugin.scheduleAlarm(schedule) { scheduleError = it.exceptionOrNull() }
            assertEquals("INVALID_ALARM_ID", assertIs<FlutterError>(scheduleError).code)

            var cancelError: Throwable? = null
            plugin.cancelAlarm(id) { cancelError = it.exceptionOrNull() }
            assertEquals("INVALID_ALARM_ID", assertIs<FlutterError>(cancelError).code)

            var stopError: Throwable? = null
            plugin.stopAlarm(id) { stopError = it.exceptionOrNull() }
            assertEquals("INVALID_ALARM_ID", assertIs<FlutterError>(stopError).code)
            Mockito.verifyNoInteractions(context)
        }
    }

    @Test
    fun stopAlarmSendsTheStopActionOnlyForTheRingingAlarm() {
        val context = Mockito.mock(Context::class.java)
        val plugin = Mockito.mock(WarmAlarmPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        setPrivateField(plugin, "context", context)
        try {
            Mockito.mockConstruction(Intent::class.java).use { intents ->
                for ((ringing, currentId) in listOf(false to null, false to 42L, true to 41L)) {
                    WarmAlarmForegroundService.isRinging = ringing
                    WarmAlarmForegroundService.currentAlarmId = currentId
                    var stopped: Boolean? = null
                    plugin.stopAlarm(42) { stopped = it.getOrThrow() }
                    assertEquals(false, stopped, "ringing=$ringing currentId=$currentId")
                }
                Mockito.verifyNoInteractions(context)
                assertEquals(0, intents.constructed().size)

                WarmAlarmForegroundService.isRinging = true
                WarmAlarmForegroundService.currentAlarmId = 42
                var stopped: Boolean? = null
                plugin.stopAlarm(42) { stopped = it.getOrThrow() }

                assertEquals(true, stopped)
                val intent = intents.constructed().single()
                Mockito.verify(intent).setAction(WarmAlarmForegroundService.ACTION_STOP)
                Mockito.verify(intent).putExtra(WarmAlarmForegroundService.EXTRA_ALARM_ID, 42L)
                Mockito.verify(context).startService(intent)
            }
        } finally {
            WarmAlarmForegroundService.isRinging = false
            WarmAlarmForegroundService.currentAlarmId = null
        }
    }

    @Test
    fun invalidRescheduleDoesNotCreateABackend() {
        val context = Mockito.mock(Context::class.java) { throw AssertionError("Invalid reschedule reached Android: ${it.method.name}") }
        val error = assertFailsWith<FlutterError> { WarmAlarmPlugin.rescheduleAlarm(context, 4_294_967_296L, 1_234) }
        assertEquals("INVALID_ALARM_ID", error.code)
        Mockito.verifyNoInteractions(context)
    }

    @Test
    fun androidReportsWakeCheckAsSupported() {
        val plugin = Mockito.mock(WarmAlarmPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        lateinit var capabilities: WarmAlarmCapabilitiesWire

        plugin.getCapabilities { result ->
            capabilities = result.getOrThrow()
        }

        assertEquals(WarmAlarmSupportStatusWire.SUPPORTED, capabilities.wakeCheck)
    }

    @Test
    fun alarmSchedulingDoesNotRequireAnAttachedFlutterEngine() {
        val backend = FakeAlarmSchedulingBackend()

        WarmAlarmPlugin.scheduleAlarm(
            backend = backend,
            fireAtMillis = 1_234,
            sdkInt = 30,
        )

        assertEquals(listOf(1_234L), backend.exactSchedules)
        assertEquals(emptyList(), backend.inexactSchedules)
    }

    @Test
    fun preMarshmallowSchedulingUsesTheLegacyExactApi() {
        val backend = FakeAlarmSchedulingBackend()

        WarmAlarmPlugin.scheduleAlarm(
            backend = backend,
            fireAtMillis = 1_234,
            sdkInt = 22,
        )

        assertEquals(listOf(1_234L), backend.legacySchedules)
        assertEquals(emptyList(), backend.exactSchedules)
    }

    @Test
    fun configurationChangeKeepsPendingNotificationPermissionCallback() {
        val plugin = Mockito.mock(WarmAlarmPlugin::class.java, Mockito.CALLS_REAL_METHODS)
        val activityBinding = Mockito.mock(ActivityPluginBinding::class.java)
        val callback: (Result<WarmAlarmRemediationResultWire>) -> Unit = {}
        setPrivateField(plugin, "activityBinding", activityBinding)
        setPrivateField(plugin, "pendingNotificationPermissionCallback", callback)

        plugin.onDetachedFromActivityForConfigChanges()

        assertSame(callback, getPrivateField(plugin, "pendingNotificationPermissionCallback"))
        Mockito.verify(activityBinding).removeRequestPermissionsResultListener(plugin)
    }
}

private fun setPrivateField(
    instance: Any,
    fieldName: String,
    value: Any?,
) {
    instance.javaClass
        .getDeclaredField(fieldName)
        .apply { isAccessible = true }
        .set(instance, value)
}

private fun getPrivateField(
    instance: Any,
    fieldName: String,
): Any? =
    instance.javaClass
        .getDeclaredField(fieldName)
        .apply { isAccessible = true }
        .get(instance)

private class FakeAlarmSchedulingBackend : AlarmSchedulingBackend {
    val legacySchedules = mutableListOf<Long>()
    val exactSchedules = mutableListOf<Long>()
    val inexactSchedules = mutableListOf<Long>()

    override fun canScheduleExactAlarms(): Boolean = true

    override fun scheduleLegacy(fireAtMillis: Long) {
        legacySchedules += fireAtMillis
    }

    override fun scheduleExact(fireAtMillis: Long) {
        exactSchedules += fireAtMillis
    }

    override fun scheduleInexact(fireAtMillis: Long) {
        inexactSchedules += fireAtMillis
    }
}
