package com.andrew.alarm

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
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
import org.mockito.ArgumentCaptor
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmAlarmForegroundServiceTest {
    @Test
    fun retainedNotificationsDetachOnApi24AndLater() {
        for (sdk in listOf(24, 29)) {
            for (action in listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE)) {
                AndroidSdkOverride(sdk).use {
                    PlaybackHarness(keepNotification = true).use { harness ->
                        harness.fire(72)
                        harness.command(action, 72)
                        val order = Mockito.inOrder(harness.service, harness.notifications)
                        order.verify(harness.service).stopForeground(Service.STOP_FOREGROUND_DETACH)
                        order.verify(harness.notifications).notify(Mockito.eq(2001), Mockito.any(Notification::class.java))
                        order.verify(harness.service).stopSelf()
                        @Suppress("DEPRECATION")
                        Mockito.verify(harness.service, Mockito.never()).stopForeground(false)
                        Mockito.verify(harness.service).stopSelf()
                        assertCompletedNotification(harness)
                    }
                }
            }
        }
    }

    @Test
    fun retainedNotificationsBecomeOrdinaryNotificationsBeforeApi24() {
        for (sdk in listOf(19, 22, 23)) {
            for (action in listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE)) {
                AndroidSdkOverride(sdk).use {
                    PlaybackHarness(keepNotification = true).use { harness ->
                        harness.fire(72)
                        harness.command(action, 72)
                        val order = Mockito.inOrder(harness.service, harness.notifications)
                        @Suppress("DEPRECATION")
                        order.verify(harness.service).stopForeground(true)
                        order.verify(harness.notifications).notify(Mockito.eq(2001), Mockito.any(Notification::class.java))
                        order.verify(harness.service).stopSelf()
                        Mockito.verify(harness.service, Mockito.never()).stopForeground(Mockito.anyInt())
                        Mockito.verify(harness.notifications).notify(Mockito.eq(2001), Mockito.any(Notification::class.java))
                        Mockito.verify(harness.service).stopSelf()
                        val retained = assertCompletedNotification(harness)
                        assertTrue(retained.priority <= Notification.PRIORITY_LOW)
                        assertEquals(null, retained.sound)
                        assertEquals(null, retained.vibrate)
                        assertEquals(0, retained.defaults)
                    }
                }
            }
        }
    }

    @Test
    fun completedNotificationsAreRemovedWhenRetentionIsDisabled() {
        for (sdk in listOf(19, 24, 29)) {
            for (action in listOf(WarmAlarmForegroundService.ACTION_STOP, WarmAlarmForegroundService.ACTION_SNOOZE)) {
                AndroidSdkOverride(sdk).use {
                    PlaybackHarness().use { harness ->
                        harness.fire(72)
                        harness.command(action, 72)
                        @Suppress("DEPRECATION")
                        Mockito.verify(harness.service).stopForeground(true)
                        Mockito
                            .verify(
                                harness.notifications,
                                Mockito.never(),
                            ).notify(Mockito.anyInt(), Mockito.any(Notification::class.java))
                    }
                }
            }
        }
    }

    private fun assertCompletedNotification(harness: PlaybackHarness): Notification {
        val capture = ArgumentCaptor.forClass(Notification::class.java)
        Mockito.verify(harness.notifications).notify(Mockito.eq(2001), capture.capture())
        val retained = capture.value
        assertTrue(retained.actions.isEmpty())
        assertEquals(null, retained.fullScreenIntent)
        assertEquals(
            0,
            retained.flags and (Notification.FLAG_FOREGROUND_SERVICE or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR),
        )
        assertTrue(retained.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
        return retained
    }

    @Test
    fun api19PlaybackUsesTheLegacyAlarmStream() {
        AndroidSdkOverride(19).use {
            PlaybackHarness().use { harness ->
                harness.fire(72)
                val player = harness.players.single()
                @Suppress("DEPRECATION")
                Mockito.verify(player).setAudioStreamType(AudioManager.STREAM_ALARM)
                Mockito.verify(player, Mockito.never()).setAudioAttributes(Mockito.any(AudioAttributes::class.java))
                assertTrue(player.isPlaying)
            }
        }
    }

    @Test
    fun api21PlaybackKeepsAudioAttributes() {
        AndroidSdkOverride(21).use {
            PlaybackHarness().use { harness ->
                harness.fire(72)
                val player = harness.players.single()
                Mockito.verify(player).setAudioAttributes(Mockito.any(AudioAttributes::class.java))
                @Suppress("DEPRECATION")
                Mockito.verify(player, Mockito.never()).setAudioStreamType(Mockito.anyInt())
                assertTrue(player.isPlaying)
            }
        }
    }

    @Test
    fun missingIdDoesNotStopOrReplaceCurrentPlayback() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val player = harness.players.single()

            harness.service.onStartCommand(Mockito.mock(Intent::class.java), 0, 1)

            assertTrue(player.isPlaying)
            assertEquals(71L, WarmAlarmForegroundService.currentAlarmId)
            Mockito.verify(player, Mockito.never()).release()
            Mockito.verify(harness.service, Mockito.never()).stopSelf()
        }
    }

    @Test
    fun minusOnePlaybackFailureStillEmitsTheFailureEvent() {
        assertInitializationFailure(alarmId = -1) { player ->
            Mockito.doThrow(IllegalStateException("Initialization failed")).`when`(player).prepare()
        }
    }

    @Test
    fun minusOneIsAPlayableAndCancellableAlarmId() {
        PlaybackHarness().use { harness ->
            harness.fire(-1)
            assertEquals(1, harness.players.size, "An explicit -1 ID must start playback")
            val player = harness.players.single()
            assertTrue(player.isPlaying)
            assertEquals(-1L, WarmAlarmForegroundService.currentAlarmId)

            harness.command(WarmAlarmForegroundService.ACTION_CANCEL_CURRENT, -1)

            Mockito.verify(player).release()
            assertFalse(WarmAlarmForegroundService.isRinging)
        }
    }

    @Test
    fun unsupportedCommandDoesNotReplaceCurrentPlayback() {
        PlaybackHarness().use { harness ->
            harness.fire(71)
            val player = harness.players.single()

            harness.fire(4_294_967_296L)

            assertEquals(1, harness.players.size)
            Mockito.verify(player, Mockito.never()).release()
            assertTrue(player.isPlaying)
            assertEquals(71L, WarmAlarmForegroundService.currentAlarmId)
            val event =
                WarmAlarmEventQueueStore
                    .create(harness.service)
                    .loadAll()
                    .single()
                    .event
            assertEquals(WarmAlarmFailureCodeWire.INVALID_ARGUMENTS, event.failure?.code)
        }
    }

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

    @Test
    fun dataSourceFailureReleasesPlayer() {
        assertInitializationFailure { player ->
            Mockito
                .doThrow(IllegalArgumentException("Initialization failed"))
                .`when`(player)
                .setDataSource(Mockito.any(Context::class.java), Mockito.nullable(Uri::class.java))
        }
    }

    @Test
    fun prepareFailureReleasesPlayer() {
        assertInitializationFailure { player ->
            Mockito.doThrow(IllegalStateException("Initialization failed")).`when`(player).prepare()
        }
    }

    @Test
    fun startFailureReleasesPlayer() {
        assertInitializationFailure { player ->
            Mockito.doThrow(IllegalStateException("Initialization failed")).`when`(player).start()
        }
    }

    @Test
    fun releaseFailurePreservesInitializationFailure() {
        assertInitializationFailure { player ->
            Mockito.doThrow(IllegalStateException("Initialization failed")).`when`(player).prepare()
            Mockito.doThrow(IllegalStateException("Release failed")).`when`(player).release()
        }
    }

    private fun assertInitializationFailure(
        alarmId: Long = 71,
        configurePlayer: (MediaPlayer) -> Unit,
    ) {
        PlaybackHarness(configurePlayer).use { harness ->
            harness.fire(alarmId)

            val player = harness.players.single()
            Mockito.verify(player).release()
            Mockito.verify(player, Mockito.never()).stop()
            assertFalse(player.isPlaying)
            assertFalse(harness.vibration.active)
            assertTrue(harness.fadeCallbacks.isEmpty())
            assertTrue(harness.enforcementCallbacks.isEmpty())
            Mockito.verify(harness.service).stopSelf()
            val event =
                WarmAlarmEventQueueStore
                    .create(harness.service)
                    .loadAll()
                    .single()
                    .event
            assertEquals(alarmId, event.alarmId)
            assertEquals(WarmAlarmEventTypeWire.FAILED, event.type)
            assertEquals(WarmAlarmFailureCodeWire.AUDIO_PLAYBACK_FAILED, event.failure?.code)
            assertEquals("Initialization failed", event.failure?.message)
        }
    }
}

private class PlaybackHarness(
    configurePlayer: (MediaPlayer) -> Unit = {},
    private val keepNotification: Boolean = false,
) : AutoCloseable {
    val notifications = Mockito.mock(NotificationManager::class.java)
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
                configurePlayer(player)
            }.also { resources += it }
    val players: List<MediaPlayer> get() = constructedPlayers.constructed()

    init {
        WarmAlarmForegroundService.isRinging = false
        WarmAlarmForegroundService.currentAlarmId = null
        setField("fadeStepHandler", handler(fadeCallbacks))
        setField("volumeEnforcerHandler", handler(enforcementCallbacks))
        setField("vibrationController", WarmAlarmVibrationController(vibration))

        Mockito.doReturn(service).`when`(service).createDeviceProtectedStorageContext()
        Mockito.doReturn(null).`when`(service).getSystemService(Context.USER_SERVICE)
        val preferences = Mockito.mock(SharedPreferences::class.java)
        val editor = Mockito.mock(SharedPreferences.Editor::class.java, Mockito.RETURNS_SELF)
        val schedules =
            JSONArray()
                .put(
                    WarmAlarmStore.encode(schedule(71)),
                ).put(
                    WarmAlarmStore.encode(schedule(72)),
                ).put(WarmAlarmStore.encode(schedule(-1)))
                .put(WarmAlarmStore.encode(schedule(4_294_967_296L)))
        val storedStrings = mutableMapOf("schedules" to schedules.toString())
        Mockito.doReturn(preferences).`when`(service).getSharedPreferences(Mockito.anyString(), Mockito.anyInt())
        Mockito.`when`(preferences.getString(Mockito.anyString(), Mockito.nullable(String::class.java))).thenAnswer {
            storedStrings[it.getArgument<String>(0)] ?: it.getArgument<String?>(1)
        }
        Mockito.`when`(preferences.edit()).thenReturn(editor)
        Mockito.`when`(editor.putString(Mockito.anyString(), Mockito.anyString())).thenAnswer {
            storedStrings[it.getArgument<String>(0)] = it.getArgument<String>(1)
            editor
        }
        Mockito.`when`(editor.commit()).thenReturn(true)
        Mockito.doReturn("com.andrew.alarm").`when`(service).getPackageName()
        Mockito.doNothing().`when`(service).startForeground(Mockito.anyInt(), Mockito.any(Notification::class.java))
        @Suppress("DEPRECATION")
        Mockito.doNothing().`when`(service).stopForeground(Mockito.anyBoolean())
        Mockito.doNothing().`when`(service).stopForeground(Mockito.anyInt())
        Mockito.doNothing().`when`(service).stopSelf()
        val audioManager = Mockito.mock(AudioManager::class.java)
        Mockito.`when`(audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)).thenReturn(10)
        Mockito.doReturn(audioManager).`when`(service).getSystemService(Context.AUDIO_SERVICE)
        Mockito.doReturn(Mockito.mock(AlarmManager::class.java)).`when`(service).getSystemService(Context.ALARM_SERVICE)
        Mockito.doReturn(notifications).`when`(service).getSystemService(Context.NOTIFICATION_SERVICE)

        val pendingIntents = Mockito.mockStatic(PendingIntent::class.java)
        resources += pendingIntents
        pendingIntents
            .`when`<PendingIntent> {
                PendingIntent.getBroadcast(
                    Mockito.any(Context::class.java),
                    Mockito.anyInt(),
                    Mockito.any(Intent::class.java),
                    Mockito.anyInt(),
                )
            }.thenReturn(Mockito.mock(PendingIntent::class.java))
        resources += Mockito.mockStatic(Uri::class.java)
        resources += Mockito.mockConstruction(Intent::class.java)
        resources +=
            Mockito.mockConstruction(NotificationCompat.Builder::class.java, Mockito.withSettings().defaultAnswer(Mockito.RETURNS_SELF)) {
                builder,
                _,
                ->
                val notification =
                    Notification().apply {
                        priority = Notification.PRIORITY_HIGH
                        flags = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR or Notification.FLAG_FOREGROUND_SERVICE
                        defaults = Notification.DEFAULT_ALL
                        sound = Mockito.mock(Uri::class.java)
                        vibrate = longArrayOf(0, 200)
                        fullScreenIntent = Mockito.mock(PendingIntent::class.java)
                        actions = arrayOf(Mockito.mock(Notification.Action::class.java))
                    }
                Mockito.`when`(builder.build()).thenReturn(notification)
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
        Mockito.`when`(intent.hasExtra(WarmAlarmForegroundService.EXTRA_ALARM_ID)).thenReturn(true)
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
            notification = WarmAlarmNotificationWire(title = "Alarm", body = "Overlap", keepNotificationAfterAlarmEnds = keepNotification),
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
        players.forEach { runCatching { it.release() } }
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
