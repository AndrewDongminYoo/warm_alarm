package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WarmAlarmIdRecoveryTest {
    @Test
    fun wakeCheckFireWithMissingIdHasNoSideEffects() {
        assertMissingIdHasNoSideEffects(WarmAlarmReceiver.ACTION_WAKE_CHECK_FIRE)
    }

    @Test
    fun wakeCheckDismissWithMissingIdHasNoSideEffects() {
        assertMissingIdHasNoSideEffects(WarmAlarmReceiver.ACTION_WAKE_CHECK_DISMISS)
    }

    private fun assertMissingIdHasNoSideEffects(action: String) {
        IdRecoveryHarness().use { harness ->
            val storedBefore = harness.storedValues()
            Mockito.clearInvocations(harness.context)

            WarmAlarmReceiver().onReceive(harness.context, harness.deliveryIntent(null, action))

            Mockito.verifyNoInteractions(harness.context)
            assertTrue(harness.registeredIds.isEmpty())
            assertEquals(storedBefore, harness.storedValues())
            assertTrue(harness.events().isEmpty())
        }
    }

    @Test
    fun supportedSnoozeAndRetriggerIdsReachTheSharedFactory() {
        IdRecoveryHarness().use { harness ->
            for (id in harness.supportedIds) {
                WarmAlarmPlugin.rescheduleAlarm(harness.context, id, 1_234)
                WarmAlarmPlugin.rescheduleAlarm(harness.context, id, 1_234, isRetrigger = true)
            }
            assertEquals(harness.supportedIds.flatMap { listOf(it, it) }, harness.registeredIds)
        }
    }

    @Test
    fun wakeCheckActionsAcceptMinusOneAndRejectUnsupportedIds() {
        for (action in listOf(WarmAlarmReceiver.ACTION_WAKE_CHECK_FIRE, WarmAlarmReceiver.ACTION_WAKE_CHECK_DISMISS)) {
            IdRecoveryHarness().use { harness ->
                WarmAlarmReceiver().onReceive(harness.context, harness.deliveryIntent(-1, action))
                assertTrue(harness.events().isNotEmpty())
                assertTrue(harness.events().all { it.alarmId == -1L })
                assertTrue(harness.registeredIds.isNotEmpty())
                assertTrue(harness.registeredIds.all { it == -1L })
                harness.registeredIds.clear()

                WarmAlarmReceiver().onReceive(harness.context, harness.deliveryIntent(4_294_967_296L, action))

                assertTrue(harness.registeredIds.isEmpty())
                assertEquals(
                    WarmAlarmFailureCodeWire.INVALID_ARGUMENTS,
                    harness
                        .events()
                        .last()
                        .failure
                        ?.code,
                )
            }
        }
    }

    @Test
    fun bootRestoresSupportedIdsAndReportsUnsupportedRecords() {
        IdRecoveryHarness().use { harness ->
            val intent = Mockito.mock(Intent::class.java)
            Mockito.`when`(intent.action).thenReturn(Intent.ACTION_BOOT_COMPLETED)

            WarmAlarmBootReceiver().onReceive(harness.context, intent)

            assertEquals(harness.supportedIds, harness.registeredIds)
            assertEquals(harness.unsupportedIds, harness.events().map { it.alarmId })
            assertTrue(harness.events().all { it.failure?.code == WarmAlarmFailureCodeWire.INVALID_ARGUMENTS })
            assertEquals(harness.allIds.toSet(), WarmAlarmStore.loadAll(harness.context).keys)
        }
    }

    @Test
    fun initializationDoesNotRestoreAnUnsupportedAlias() {
        IdRecoveryHarness().use { harness ->
            val plugin = harness.plugin()
            var completed = false

            plugin.initialize {
                it.getOrThrow()
                completed = true
            }

            assertTrue(completed)
            assertEquals(harness.supportedIds, harness.registeredIds)
            assertEquals(harness.unsupportedIds, harness.events().map { it.alarmId })
        }
    }

    @Test
    fun receiverDeliversMinusOneAndRejectsMissingOrUnsupportedIds() {
        IdRecoveryHarness().use { harness ->
            val receiver = WarmAlarmReceiver()
            receiver.onReceive(harness.context, harness.deliveryIntent(-1))
            receiver.onReceive(harness.context, harness.deliveryIntent(null))
            receiver.onReceive(harness.context, harness.deliveryIntent(4_294_967_296L))

            Mockito.verify(harness.context).startService(Mockito.any(Intent::class.java))
            assertEquals(listOf(-1L, 4_294_967_296L), harness.events().map { it.alarmId })
            assertEquals(listOf(WarmAlarmEventTypeWire.FIRED, WarmAlarmEventTypeWire.FAILED), harness.events().map { it.type })
        }
    }

    @Test
    fun cancelAllNeverLooksUpUnsupportedIds() {
        IdRecoveryHarness().use { harness ->
            harness.plugin().cancelAllAlarms { it.getOrThrow() }

            assertTrue(harness.registeredIds.all { it in harness.supportedIds })
            assertTrue(WarmAlarmStore.loadAll(harness.context).isEmpty())
        }
    }
}

private class IdRecoveryHarness : AutoCloseable {
    val supportedIds = listOf(Int.MIN_VALUE.toLong(), -1L, 0L, Int.MAX_VALUE.toLong())
    val unsupportedIds = listOf(Int.MIN_VALUE.toLong() - 1, Int.MAX_VALUE.toLong() + 1, 4_294_967_296L, Long.MIN_VALUE, Long.MAX_VALUE)
    val allIds = supportedIds + unsupportedIds
    val context = Mockito.mock(Context::class.java)
    val registeredIds = mutableListOf<Long>()
    private val alarmManager = Mockito.mock(AlarmManager::class.java)
    private val resources = mutableListOf<AutoCloseable>()
    private val values = mutableMapOf<String, String>()

    init {
        val preferences = Mockito.mock(SharedPreferences::class.java)
        val editor = Mockito.mock(SharedPreferences.Editor::class.java, Mockito.RETURNS_SELF)
        Mockito.`when`(context.getSharedPreferences(Mockito.anyString(), Mockito.anyInt())).thenReturn(preferences)
        Mockito.`when`(context.packageName).thenReturn("com.andrew.alarm")
        Mockito.`when`(context.getSystemService(Context.ALARM_SERVICE)).thenReturn(alarmManager)
        Mockito.`when`(context.getSystemService(Context.NOTIFICATION_SERVICE)).thenReturn(Mockito.mock(NotificationManager::class.java))
        Mockito.`when`(preferences.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            values[it.getArgument<String>(0)] ?: it.getArgument<String?>(1)
        }
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        Mockito.`when`(editor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            values[it.getArgument<String>(0)] = it.getArgument<String>(1)
            editor
        }
        Mockito.`when`(editor.commit()).thenReturn(true)
        Mockito.`when`(editor.remove(Mockito.anyString())).thenAnswer {
            values.remove(it.getArgument<String>(0))
            editor
        }
        Mockito.`when`(editor.clear()).thenAnswer {
            values.clear()
            editor
        }
        resources += Mockito.mockStatic(android.net.Uri::class.java)
        resources +=
            Mockito.mockConstruction(Intent::class.java) { intent, _ ->
                var id: Long? = null
                Mockito.`when`(intent.putExtra(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
                    id = it.getArgument<Long>(1)
                    intent
                }
                Mockito.`when`(intent.getLongExtra(Mockito.anyString(), Mockito.anyLong())).thenAnswer {
                    id ?: it.getArgument<Long>(1)
                }
            }
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
                registeredIds += it.getArgument<Intent>(2).getLongExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, -99)
                Mockito.mock(PendingIntent::class.java)
            }
        resources += pending
        for (id in allIds) {
            WarmAlarmStore.save(
                context,
                WarmAlarmScheduleWire(
                    id = id,
                    scheduledAtMillis = System.currentTimeMillis() + 60_000,
                    notification = WarmAlarmNotificationWire(title = "ID", body = "Recovery", keepNotificationAfterAlarmEnds = false),
                    audio = WarmAlarmAudioWire(loop = true, vibrate = false, volumeEnforced = false),
                    wakeCheck = WarmAlarmWakeCheckWire(checkDelayMillis = 5_000, maxRetriggers = 0),
                    androidFullScreenIntent = false,
                ),
            )
        }
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

    fun deliveryIntent(
        id: Long?,
        deliveryAction: String = WarmAlarmReceiver.ACTION_FIRE,
    ): Intent =
        Mockito.mock(Intent::class.java).apply {
            Mockito.`when`(action).thenReturn(deliveryAction)
            Mockito.`when`(hasExtra(WarmAlarmReceiver.EXTRA_ALARM_ID)).thenReturn(id != null)
            Mockito.`when`(getLongExtra(WarmAlarmReceiver.EXTRA_ALARM_ID, -1L)).thenReturn(id ?: -1L)
        }

    fun events() = WarmAlarmEventQueueStore.create(context).loadAll().map { it.event }

    fun storedValues() = values.toMap()

    override fun close() {
        resources.asReversed().forEach { it.close() }
    }
}
