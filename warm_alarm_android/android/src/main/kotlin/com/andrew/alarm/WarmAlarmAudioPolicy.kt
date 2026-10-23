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
    private const val FADE_IN_MAX_STEPS = 10L
    private const val FADE_IN_MIN_STEP_MILLIS = 100L

    /**
     * Returns the volume points the service plays.
     * Explicit [fadeSteps] win. Otherwise a positive [fadeInDurationMillis] becomes a linear ramp from silence at 0 ms
     * to [volume], or to 1.0 when [volume] is null. The ramp uses 10 steps or one step per 100 ms, whichever is fewer.
     */
    fun resolveFadeSteps(
        fadeSteps: List<WarmAlarmVolumeFadeStepWire>?,
        fadeInDurationMillis: Long?,
        volume: Double?,
    ): List<WarmAlarmVolumeFadeStepWire>? {
        if (fadeSteps != null) return fadeSteps
        if (fadeInDurationMillis == null || fadeInDurationMillis <= 0L) return null
        val target = (volume ?: 1.0).coerceIn(0.0, 1.0)
        val count = (fadeInDurationMillis / FADE_IN_MIN_STEP_MILLIS).coerceIn(1L, FADE_IN_MAX_STEPS)
        return (0L..count).map { index ->
            WarmAlarmVolumeFadeStepWire(
                timeMillis = fadeInDurationMillis * index / count,
                volume = if (index == count) target else target * index / count,
            )
        }
    }

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
