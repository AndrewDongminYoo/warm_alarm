package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmReadinessTest {
    private val granted =
        WarmAlarmPermissionStateWire(notificationsGranted = true, exactAlarmGranted = true, fullScreenIntentGranted = true)

    @Test
    fun exemptAppWithEveryPermissionIsReady() {
        val readiness = WarmAlarmPlugin.deriveReadiness(granted, batteryOptimizationMayDelay = false)

        assertEquals(WarmAlarmReadinessLevelWire.READY, readiness.level)
        assertEquals(emptyList(), readiness.reasons)
    }

    @Test
    fun batteryOptimizationAloneLimitsReadiness() {
        val readiness = WarmAlarmPlugin.deriveReadiness(granted, batteryOptimizationMayDelay = true)

        assertEquals(WarmAlarmReadinessLevelWire.LIMITED, readiness.level)
        assertEquals(listOf(WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY), readiness.reasons)
    }

    @Test
    fun batteryOptimizationFollowsPermissionReasons() {
        val readiness =
            WarmAlarmPlugin.deriveReadiness(granted.copy(exactAlarmGranted = false), batteryOptimizationMayDelay = true)

        assertEquals(WarmAlarmReadinessLevelWire.LIMITED, readiness.level)
        assertEquals(
            listOf(
                WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED,
                WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY,
            ),
            readiness.reasons,
        )
    }

    @Test
    fun batteryOptimizationIsNotInspectedBeforeMarshmallow() {
        val context = Mockito.mock(Context::class.java) { throw AssertionError("API 22 reached Android: ${it.method.name}") }

        assertFalse(WarmAlarmPlugin.batteryOptimizationMayDelay(context, sdkInt = 22))
        Mockito.verifyNoInteractions(context)
    }

    @Test
    fun batteryOptimizationReflectsThePowerManagerExemption() {
        assertFalse(WarmAlarmPlugin.batteryOptimizationMayDelay(contextWithPowerManager(ignoring = true), sdkInt = 23))
        assertTrue(WarmAlarmPlugin.batteryOptimizationMayDelay(contextWithPowerManager(ignoring = false), sdkInt = 23))
    }

    @Test
    fun missingPowerServiceReportsNoBatteryLimit() {
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(context.packageName).thenReturn(PACKAGE_NAME)

        assertFalse(WarmAlarmPlugin.batteryOptimizationMayDelay(context, sdkInt = 23))
    }

    @Test
    fun getReadinessReportsBatteryOptimizationForANonExemptApp() {
        ReadinessHarness(sdkInt = 23, ignoringBatteryOptimizations = false).use { harness ->
            lateinit var readiness: WarmAlarmReadinessWire
            harness.plugin().getReadiness { readiness = it.getOrThrow() }

            assertEquals(WarmAlarmReadinessLevelWire.LIMITED, readiness.level)
            assertEquals(listOf(WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY), readiness.reasons)
        }
    }

    @Test
    fun getReadinessIsReadyForAnExemptApp() {
        ReadinessHarness(sdkInt = 23, ignoringBatteryOptimizations = true).use { harness ->
            lateinit var readiness: WarmAlarmReadinessWire
            harness.plugin().getReadiness { readiness = it.getOrThrow() }

            assertEquals(WarmAlarmReadinessLevelWire.READY, readiness.level)
            assertEquals(emptyList(), readiness.reasons)
        }
    }

    @Test
    fun batterySettingsOpenTheOptimizationList() {
        ReadinessHarness(sdkInt = 23, ignoringBatteryOptimizations = false).use { harness ->
            lateinit var result: WarmAlarmRemediationResultWire
            harness.plugin().openReadinessSettings(WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY) {
                result = it.getOrThrow()
            }

            assertEquals(WarmAlarmRemediationStatusWire.COMPLETED, result.status)
            assertEquals(listOf(listOf<Any?>(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)), harness.intentArguments)
            Mockito.verify(harness.context).startActivity(Mockito.any(Intent::class.java))
            assertEquals(listOf(WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY), result.readiness.reasons)
        }
    }

    @Test
    fun batterySettingsAreUnsupportedBeforeMarshmallow() {
        ReadinessHarness(sdkInt = 22, ignoringBatteryOptimizations = false).use { harness ->
            lateinit var result: WarmAlarmRemediationResultWire
            harness.plugin().openReadinessSettings(WarmAlarmReadinessReasonWire.BATTERY_OPTIMIZATION_MAY_DELAY) {
                result = it.getOrThrow()
            }

            assertEquals(WarmAlarmRemediationStatusWire.UNSUPPORTED, result.status)
            assertEquals(emptyList(), harness.intentArguments)
            Mockito.verify(harness.context, Mockito.never()).startActivity(Mockito.any(Intent::class.java))
            assertEquals(emptyList(), result.readiness.reasons)
        }
    }

    private fun contextWithPowerManager(ignoring: Boolean): Context {
        val context = Mockito.mock(Context::class.java)
        val powerManager = Mockito.mock(PowerManager::class.java)
        Mockito.`when`(context.packageName).thenReturn(PACKAGE_NAME)
        Mockito.`when`(context.getSystemService(Context.POWER_SERVICE)).thenReturn(powerManager)
        Mockito.`when`(powerManager.isIgnoringBatteryOptimizations(PACKAGE_NAME)).thenReturn(ignoring)
        return context
    }
}

private const val PACKAGE_NAME = "com.andrew.alarm"

/** A plugin whose permissions are all granted on [sdkInt] (API 22 or 23), differing only in the battery exemption. */
private class ReadinessHarness(
    sdkInt: Int,
    ignoringBatteryOptimizations: Boolean,
) : AutoCloseable {
    val context: Context = Mockito.mock(Context::class.java)
    val intentArguments = mutableListOf<List<Any?>>()
    private val resources = mutableListOf<AutoCloseable>()

    init {
        resources += AndroidSdkOverride(sdkInt)
        val powerManager = Mockito.mock(PowerManager::class.java)
        Mockito.`when`(powerManager.isIgnoringBatteryOptimizations(PACKAGE_NAME)).thenReturn(ignoringBatteryOptimizations)
        Mockito.`when`(context.packageName).thenReturn(PACKAGE_NAME)
        Mockito.`when`(context.getSystemService(Context.POWER_SERVICE)).thenReturn(powerManager)
        resources += Mockito.mockConstruction(Intent::class.java) { _, construction -> intentArguments += construction.arguments() }
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
            "alarmManager" to Mockito.mock(AlarmManager::class.java),
            "notificationManager" to Mockito.mock(NotificationManager::class.java),
        )) {
            WarmAlarmPlugin::class.java
                .getDeclaredField(name)
                .apply { isAccessible = true }
                .set(plugin, value)
        }
        return plugin
    }

    override fun close() {
        resources.asReversed().forEach { it.close() }
    }
}
