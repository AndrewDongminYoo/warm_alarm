package com.andrew.alarm

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

class WarmAlarmPluginTest {
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
