package com.andrew.alarm

internal enum class WarmAlarmAudioSource {
    FILE,
    ASSET,
    DEFAULT_ALARM,
}

internal data class WarmAlarmAudioSelection(
    val source: WarmAlarmAudioSource,
    val path: String?,
    val loop: Boolean,
)

internal object WarmAlarmAudioPolicy {
    fun select(
        filePath: String?,
        assetPath: String?,
        loop: Boolean,
        canReadCredentialProtectedFiles: Boolean,
        fileReadableDuringDirectBoot: Boolean,
    ): WarmAlarmAudioSelection {
        val configuredFile = filePath?.takeUnless { it.isBlank() }
        if (configuredFile != null && (canReadCredentialProtectedFiles || fileReadableDuringDirectBoot)) {
            return WarmAlarmAudioSelection(WarmAlarmAudioSource.FILE, configuredFile, loop)
        }

        val configuredAsset = assetPath?.takeUnless { it.isBlank() }
        if (configuredAsset != null) {
            return WarmAlarmAudioSelection(WarmAlarmAudioSource.ASSET, configuredAsset, loop)
        }

        return WarmAlarmAudioSelection(WarmAlarmAudioSource.DEFAULT_ALARM, null, true)
    }

    fun enforceSystemVolume(
        enabled: Boolean,
        boost: () -> Unit,
    ) {
        if (enabled) boost()
    }
}
