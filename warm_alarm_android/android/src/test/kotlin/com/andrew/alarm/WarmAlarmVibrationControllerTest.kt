package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals

class WarmAlarmVibrationControllerTest {
    @Test
    fun disabledVibrationStopsAnyExistingVibrationWithoutStartingAnother() {
        val backend = FakeVibrationBackend()
        val controller = WarmAlarmVibrationController(backend)

        controller.start(enabled = false)

        assertEquals(0, backend.startCount)
        assertEquals(1, backend.stopCount)
    }

    @Test
    fun enabledVibrationStartsRepeatingPattern() {
        val backend = FakeVibrationBackend()
        val controller = WarmAlarmVibrationController(backend)

        controller.start(enabled = true)

        assertEquals(1, backend.startCount)
    }

    @Test
    fun stopCancelsActiveVibration() {
        val backend = FakeVibrationBackend()
        val controller = WarmAlarmVibrationController(backend)
        controller.start(enabled = true)

        controller.stop()

        assertEquals(1, backend.stopCount)
    }

    @Test
    fun vibrationApiMatchesAndroidVersionBoundaries() {
        assertEquals(WarmAlarmVibrationApi.LEGACY, selectWarmAlarmVibrationApi(sdkInt = 25))
        assertEquals(WarmAlarmVibrationApi.EFFECT, selectWarmAlarmVibrationApi(sdkInt = 26))
        assertEquals(WarmAlarmVibrationApi.EFFECT, selectWarmAlarmVibrationApi(sdkInt = 30))
        assertEquals(WarmAlarmVibrationApi.MANAGER, selectWarmAlarmVibrationApi(sdkInt = 31))
    }
}

private class FakeVibrationBackend : WarmAlarmVibrationBackend {
    var startCount = 0
    var stopCount = 0

    override fun startRepeating() {
        startCount += 1
    }

    override fun stop() {
        stopCount += 1
    }
}
