package com.andrew.alarm

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmForegroundServiceTest {
    @Test
    fun replacingLoopingAlarmThenStoppingLeavesNoPlayerActive() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val first = harness.players.single()
            assertTrue(first.isPlaying)

            harness.fire(72)
            val second = harness.players.last()
            assertEquals(2, harness.players.size)
            assertTrue(second.isPlaying)
            assertEquals(72L, WarmAlarmForegroundService.currentAlarmId)
            Mockito.verify(first).setLooping(true)
            Mockito.verify(second).setLooping(true)

            harness.command(WarmAlarmForegroundService.ACTION_STOP, 72)

            assertFalse(first.isPlaying, "The replaced looping player must not survive Stop")
            assertFalse(second.isPlaying)
            Mockito.verify(first).release()
            Mockito.verify(second).release()
            assertFalse(WarmAlarmForegroundService.isRinging)
            assertEquals(null, WarmAlarmForegroundService.currentAlarmId)
        }
    }

    @Test
    fun firingTheSameAlarmAgainReleasesItsPriorPlayer() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val first = harness.players.single()

            harness.fire(71)

            assertFalse(first.isPlaying)
            Mockito.verify(first).release()
            assertTrue(harness.players.last().isPlaying)
            assertEquals(71L, WarmAlarmForegroundService.currentAlarmId)
        }
    }

    @Test
    fun replacementClearsPriorFadeVibrationAndVolumeEnforcementBeforeStarting() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val first = harness.players.single()
            assertEquals(1, harness.fadeCallbacks.size)
            // Start the enforcer once so its repeating delayed callback is pending.
            harness.enforcementCallbacks.removeAt(0).run()
            assertEquals(1, harness.enforcementCallbacks.size)
            assertTrue(harness.vibration.active)
            Mockito.clearInvocations(harness.vibration)

            harness.fire(72)
            val second = harness.players.last()

            assertTrue(harness.fadeCallbacks.isEmpty(), "The old fade must not alter the new player")
            assertTrue(harness.enforcementCallbacks.isEmpty(), "The old volume enforcer must not repeat")
            assertFalse(harness.vibration.active)
            val order = Mockito.inOrder(harness.vibration, first, second)
            order.verify(harness.vibration).stop()
            order.verify(first).stop()
            order.verify(first).release()
            order.verify(second).start()
            Mockito.verify(second).setVolume(0.8f, 0.8f)
        }
    }

    @Test
    fun replacementStillReleasesPlayerWhenStopThrows() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val first = harness.players.single()
            Mockito.doThrow(IllegalStateException("Player cannot stop")).`when`(first).stop()

            harness.fire(72)

            Mockito.verify(first).release()
            assertFalse(first.isPlaying)
            assertTrue(harness.players.last().isPlaying)
        }
    }
}

private class PlaybackHarness : AutoCloseable {
    val service = Mockito.mock(WarmAlarmForegroundService::class.java, Mockito.CALLS_REAL_METHODS)
    val fadeCallbacks = mutableListOf<Runnable>()
    val enforcementCallbacks = mutableListOf<Runnable>()
    val vibration = Mockito.spy(PlaybackVibrationBackend())
    private val resources = mutableListOf<AutoCloseable>()
    private val constructedPlayers =
        Mockito
            .mockConstruction(MediaPlayer::class.java) { player, _ ->
                var playing = false
                Mockito
                    .doAnswer {
                        playing = true
                        null
                    }.`when`(player)
                    .start()
                Mockito
                    .doAnswer {
                        playing = false
                        null
                    }.`when`(player)
                    .stop()
                Mockito
                    .doAnswer {
                        playing = false
                        null
                    }.`when`(player)
                    .release()
                Mockito.`when`(player.isPlaying).thenAnswer { playing }
            }.also { resources += it }
    val players: List<MediaPlayer> get() = constructedPlayers.constructed()

    init {
        WarmAlarmForegroundService.isRinging = false
        WarmAlarmForegroundService.currentAlarmId = null
        setField("fadeStepHandler", handler(fadeCallbacks))
        setField("volumeEnforcerHandler", handler(enforcementCallbacks))
        setField("vibrationController", WarmAlarmVibrationController(vibration))

        val preferences = Mockito.mock(SharedPreferences::class.java)
        val editor = Mockito.mock(SharedPreferences.Editor::class.java, Mockito.RETURNS_SELF)
        val schedules = JSONArray().put(WarmAlarmStore.encode(schedule(71))).put(WarmAlarmStore.encode(schedule(72)))
        Mockito.doReturn(preferences).`when`(service).getSharedPreferences(Mockito.anyString(), Mockito.anyInt())
        Mockito.`when`(preferences.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            if (it.getArgument<String>(0) == "schedules") schedules.toString() else it.getArgument<String?>(1)
        }
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        Mockito.`when`(editor.commit()).thenReturn(true)
        Mockito.doReturn("com.andrew.alarm").`when`(service).getPackageName()
        Mockito.doNothing().`when`(service).startForeground(Mockito.anyInt(), Mockito.any(Notification::class.java))
        @Suppress("DEPRECATION")
        Mockito.doNothing().`when`(service).stopForeground(Mockito.anyBoolean())
        Mockito.doNothing().`when`(service).stopSelf()
        val audioManager = Mockito.mock(AudioManager::class.java)
        Mockito.`when`(audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)).thenReturn(10)
        Mockito.doReturn(audioManager).`when`(service).getSystemService(Context.AUDIO_SERVICE)
        Mockito.doReturn(Mockito.mock(AlarmManager::class.java)).`when`(service).getSystemService(Context.ALARM_SERVICE)
        Mockito.doReturn(Mockito.mock(NotificationManager::class.java)).`when`(service).getSystemService(Context.NOTIFICATION_SERVICE)

        resources += Mockito.mockStatic(PendingIntent::class.java)
        resources += Mockito.mockStatic(Uri::class.java)
        resources += Mockito.mockConstruction(Intent::class.java)
        resources +=
            Mockito.mockConstruction(NotificationCompat.Builder::class.java, Mockito.withSettings().defaultAnswer(Mockito.RETURNS_SELF)) {
                builder,
                _,
                ->
                Mockito.`when`(builder.build()).thenReturn(Mockito.mock(Notification::class.java))
            }
        resources +=
            Mockito.mockConstruction(AudioAttributes.Builder::class.java, Mockito.withSettings().defaultAnswer(Mockito.RETURNS_SELF)) {
                builder,
                _,
                ->
                Mockito.`when`(builder.build()).thenReturn(Mockito.mock(AudioAttributes::class.java))
            }
    }

    fun fire(id: Long) = command(null, id)

    fun command(
        action: String?,
        id: Long,
    ) {
        val intent = Mockito.mock(Intent::class.java)
        Mockito.`when`(intent.action).thenReturn(action)
        Mockito.`when`(intent.getLongExtra(WarmAlarmForegroundService.EXTRA_ALARM_ID, -1L)).thenReturn(id)
        service.onStartCommand(intent, 0, 1)
    }

    private fun handler(callbacks: MutableList<Runnable>): Handler =
        Mockito.mock(Handler::class.java).apply {
            Mockito.`when`(post(Mockito.any(Runnable::class.java))).thenAnswer {
                callbacks += it.getArgument<Runnable>(0)
                true
            }
            Mockito.`when`(postDelayed(Mockito.any(Runnable::class.java), Mockito.anyLong())).thenAnswer {
                callbacks += it.getArgument<Runnable>(0)
                true
            }
            Mockito
                .doAnswer {
                    callbacks.clear()
                    null
                }.`when`(this)
                .removeCallbacksAndMessages(null)
        }

    private fun setField(
        name: String,
        value: Any,
    ) {
        WarmAlarmForegroundService::class.java
            .getDeclaredField(name)
            .apply { isAccessible = true }
            .set(service, value)
    }

    private fun schedule(id: Long) =
        WarmAlarmScheduleWire(
            id = id,
            scheduledAtMillis = 1_234,
            notification = WarmAlarmNotificationWire(title = "Alarm", body = "Overlap", keepNotificationAfterAlarmEnds = false),
            audio =
                WarmAlarmAudioWire(
                    filePath = "/alarm.wav",
                    loop = true,
                    vibrate = id == 71L,
                    volume = 0.8,
                    volumeEnforced = id == 71L,
                    fadeSteps = if (id == 71L) listOf(WarmAlarmVolumeFadeStepWire(timeMillis = 100, volume = 0.2)) else null,
                ),
            androidFullScreenIntent = false,
        )

    override fun close() {
        players.forEach { it.release() }
        resources.asReversed().forEach { it.close() }
        WarmAlarmForegroundService.isRinging = false
        WarmAlarmForegroundService.currentAlarmId = null
    }
}

private class PlaybackVibrationBackend : WarmAlarmVibrationBackend {
    var active = false

    override fun startRepeating() {
        active = true
    }

    override fun stop() {
        active = false
    }
}
