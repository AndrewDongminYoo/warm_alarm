package com.andrew.alarm

import kotlin.test.Test
import kotlin.test.assertEquals

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
}
