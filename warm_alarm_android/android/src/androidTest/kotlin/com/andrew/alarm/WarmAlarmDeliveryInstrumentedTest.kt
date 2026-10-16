package com.andrew.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Exercises native registration, receiver delivery, playback and the follow-up after Stop. */
class WarmAlarmDeliveryInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alarmId = 987_655L
    private val audioFile get() = File(context.cacheDir, "warm-alarm-delivery-test.wav")

    @Before
    fun clearBefore() = clearTestAlarm()

    @After
    fun clearAfter() = clearTestAlarm()

    @Test
    fun alarmDeliveryAndStopReachTheWakeCheckReceiver() {
        // A valid silent PCM file avoids depending on an emulator's default ringtone.
        val samples = 8_000
        val wav = ByteBuffer.allocate(44 + samples * 2).order(ByteOrder.LITTLE_ENDIAN)
        wav.put("RIFF".toByteArray()).putInt(36 + samples * 2).put("WAVEfmt ".toByteArray())
        wav
            .putInt(16)
            .putShort(1)
            .putShort(1)
            .putInt(8_000)
            .putInt(16_000)
            .putShort(2)
            .putShort(16)
        wav.put("data".toByteArray()).putInt(samples * 2)
        audioFile.writeBytes(wav.array())
        val fireAt = System.currentTimeMillis() + 1_000
        val schedule =
            WarmAlarmScheduleWire(
                id = alarmId,
                scheduledAtMillis = fireAt,
                notification = WarmAlarmNotificationWire(title = "Delivery test", body = "Alarm", keepNotificationAfterAlarmEnds = false),
                audio =
                    WarmAlarmAudioWire(
                        filePath = audioFile.absolutePath,
                        volume = 0.0,
                        loop = true,
                        vibrate = false,
                        volumeEnforced = false,
                    ),
                wakeCheck = WarmAlarmWakeCheckWire(checkDelayMillis = 1_000, maxRetriggers = 1),
                androidFullScreenIntent = false,
            )
        WarmAlarmStore.save(context, schedule)
        assertTrue(events().isEmpty())
        WarmAlarmPlugin.rescheduleAlarm(context, alarmId, fireAt)
        await("AlarmManager did not deliver the regular alarm") {
            events().any { it.type == WarmAlarmEventTypeWire.FIRED } && WarmAlarmForegroundService.currentAlarmId == alarmId
        }
        // Flush service work after handleFire sets currentAlarmId but before asserting playback.
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        assertFalse("Native audio initialization failed", events().any { it.type == WarmAlarmEventTypeWire.FAILED })
        assertTrue(WarmAlarmForegroundService.isRinging)

        context.startService(
            Intent(context, WarmAlarmForegroundService::class.java).apply {
                action = WarmAlarmForegroundService.ACTION_STOP
                putExtra(WarmAlarmForegroundService.EXTRA_ALARM_ID, alarmId)
            },
        )
        await("Stop did not register and deliver the wake check") {
            events().any { it.type == WarmAlarmEventTypeWire.WAKE_CHECK_SHOWN }
        }
        assertTrue(events().any { it.type == WarmAlarmEventTypeWire.STOPPED })
        assertFalse(WarmAlarmForegroundService.isRinging)
    }

    private fun events() =
        WarmAlarmEventQueueStore
            .create(context)
            .loadAll()
            .map { it.event }
            .filter { it.alarmId == alarmId }

    private fun await(
        message: String,
        predicate: () -> Boolean,
    ) {
        val deadline = SystemClock.elapsedRealtime() + 75_000
        while (!predicate() && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(100)
        assertTrue(message, predicate())
    }

    private fun clearTestAlarm() {
        context.stopService(Intent(context, WarmAlarmForegroundService::class.java))
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (kind in WarmAlarmIntentKind.entries) {
            WarmAlarmPendingIntents.broadcast(context, alarmId, kind, PendingIntent.FLAG_NO_CREATE)?.let {
                alarmManager.cancel(it)
                it.cancel()
            }
        }
        WarmAlarmPendingIntents.wakeCheckTrigger(context, alarmId, PendingIntent.FLAG_NO_CREATE)?.let {
            alarmManager.cancel(it)
            it.cancel()
        }
        for (action in listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE)) {
            WarmAlarmPendingIntents.serviceAction(context, alarmId, action, PendingIntent.FLAG_NO_CREATE)?.cancel()
        }
        WarmAlarmStore.clearRetriggerCount(context, alarmId)
        WarmAlarmStore.remove(context, alarmId)
        val queue = WarmAlarmEventQueueStore.create(context)
        queue.loadAll().filter { it.event.alarmId == alarmId }.forEach { queue.remove(it.occurrenceId) }
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(WarmAlarmPendingIntents.wakeCheckNotificationId(alarmId))
        audioFile.delete()
    }
}
