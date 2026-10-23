package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class WarmAlarmAudioPolicyTest {
    @Test
    fun readableFileWinsWhenBothFileAndAssetAreConfigured() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = "/data/user/0/app/voice.mp3",
                assetPath = "assets/alarm.mp3",
                loop = true,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.FILE, selection.source)
        assertEquals("/data/user/0/app/voice.mp3", selection.path)
        assertEquals(true, selection.loop)
    }

    @Test
    fun assetIsSelectedWhenFileIsUnavailableDuringDirectBoot() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = "/data/user/0/app/voice.mp3",
                assetPath = "assets/alarm.mp3",
                loop = false,
                canReadCredentialProtectedFiles = false,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.ASSET, selection.source)
        assertEquals("assets/alarm.mp3", selection.path)
        assertEquals(false, selection.loop)
    }

    @Test
    fun emptyFileFallsBackToAsset() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = "",
                assetPath = "assets/alarm.mp3",
                loop = true,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.ASSET, selection.source)
    }

    @Test
    fun whitespaceOnlyFileFallsBackToAsset() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = " ",
                assetPath = "assets/alarm.mp3",
                loop = true,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.ASSET, selection.source)
        assertEquals("assets/alarm.mp3", selection.path)
    }

    @Test
    fun whitespaceOnlyPathsUseTheDefaultAlarmSound() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = " ",
                assetPath = "\t",
                loop = false,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.DEFAULT_ALARM, selection.source)
        assertEquals(null, selection.path)
    }

    @Test
    fun nonBlankFilePathIsPreservedWithoutTrimming() {
        val filePath = " /data/user/0/app/voice message.mp3 "

        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = filePath,
                assetPath = "assets/alarm.mp3",
                loop = false,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.FILE, selection.source)
        assertEquals(filePath, selection.path)
    }

    @Test
    fun noConfiguredSourceUsesTheDefaultAlarmSound() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = null,
                assetPath = null,
                loop = false,
                canReadCredentialProtectedFiles = true,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.DEFAULT_ALARM, selection.source)
        assertEquals(true, selection.loop)
    }

    @Test
    fun lockedFileFallbackKeepsTheDefaultAlarmLooping() {
        val selection =
            WarmAlarmAudioPolicy.select(
                filePath = "/data/user/0/app/alarm.mp3",
                assetPath = null,
                loop = false,
                canReadCredentialProtectedFiles = false,
                fileReadableDuringDirectBoot = false,
            )

        assertEquals(WarmAlarmAudioSource.DEFAULT_ALARM, selection.source)
        assertEquals(true, selection.loop)
    }

    @Test
    fun systemVolumeIsBoostedOnlyWhenEnforcementIsEnabled() {
        var boostCount = 0

        WarmAlarmAudioPolicy.enforceSystemVolume(enabled = false) { boostCount += 1 }
        WarmAlarmAudioPolicy.enforceSystemVolume(enabled = true) { boostCount += 1 }

        assertEquals(1, boostCount)
    }

    @Test
    fun explicitFadeStepsWinOverFadeInDuration() {
        val steps = listOf(WarmAlarmVolumeFadeStepWire(timeMillis = 100, volume = 0.2))

        assertEquals(steps, WarmAlarmAudioPolicy.resolveFadeSteps(steps, fadeInDurationMillis = 5_000, volume = 0.8))
    }

    @Test
    fun emptyFadeStepsStillWinOverFadeInDuration() {
        val steps = emptyList<WarmAlarmVolumeFadeStepWire>()

        assertEquals(steps, WarmAlarmAudioPolicy.resolveFadeSteps(steps, fadeInDurationMillis = 5_000, volume = 0.8))
    }

    @Test
    fun missingOrZeroFadeInDurationMeansNoFade() {
        assertNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = null, volume = 0.8))
        assertNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = 0, volume = 0.8))
        assertNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = -1, volume = 0.8))
    }

    @Test
    fun longFadeInUsesTenLinearSteps() {
        val steps = requireNotNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = 5_000, volume = 0.8))

        assertEquals((0L..10L).map { it * 500 }, steps.map { it.timeMillis })
        assertEquals(0.0, steps.first().volume)
        assertEquals(0.8, steps.last().volume)
        steps.forEachIndexed { index, step -> assertEquals(0.8 * index / 10, step.volume, 1e-9) }
    }

    @Test
    fun shortFadeInUsesOneStepPer100Millis() {
        val steps = requireNotNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = 500, volume = 0.5))

        assertEquals(listOf(0L, 100L, 200L, 300L, 400L, 500L), steps.map { it.timeMillis })
        assertEquals(0.5, steps.last().volume)
    }

    @Test
    fun fadeInShorterThan100MillisJumpsToTheTargetAtItsEnd() {
        val steps = requireNotNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = 40, volume = 0.6))

        assertEquals(
            listOf(
                WarmAlarmVolumeFadeStepWire(timeMillis = 0, volume = 0.0),
                WarmAlarmVolumeFadeStepWire(timeMillis = 40, volume = 0.6),
            ),
            steps,
        )
    }

    @Test
    fun fadeInWithoutVolumeRampsToFullVolume() {
        val steps = requireNotNull(WarmAlarmAudioPolicy.resolveFadeSteps(null, fadeInDurationMillis = 1_000, volume = null))

        assertEquals(1.0, steps.last().volume)
        assertEquals(1_000L, steps.last().timeMillis)
    }
}
