package com.andrew.alarm

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

internal enum class WarmAlarmVibrationApi {
    LEGACY,
    EFFECT,
    MANAGER,
}

internal fun selectWarmAlarmVibrationApi(sdkInt: Int): WarmAlarmVibrationApi =
    when {
        sdkInt >= Build.VERSION_CODES.S -> WarmAlarmVibrationApi.MANAGER
        sdkInt >= Build.VERSION_CODES.O -> WarmAlarmVibrationApi.EFFECT
        else -> WarmAlarmVibrationApi.LEGACY
    }

internal interface WarmAlarmVibrationBackend {
    fun startRepeating()

    fun stop()
}

internal class WarmAlarmVibrationController(
    private val backend: WarmAlarmVibrationBackend,
) {
    fun start(enabled: Boolean) {
        if (enabled) {
            backend.startRepeating()
        } else {
            backend.stop()
        }
    }

    fun stop() {
        backend.stop()
    }
}

internal class AndroidWarmAlarmVibrationBackend(
    private val context: Context,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
) : WarmAlarmVibrationBackend {
    private val pattern = longArrayOf(0L, 500L, 500L)
    private var activeVibrator: Vibrator? = null

    override fun startRepeating() {
        runCatching {
            val vibrator = resolveVibrator() ?: return@runCatching
            activeVibrator = vibrator
            when (selectWarmAlarmVibrationApi(sdkInt)) {
                WarmAlarmVibrationApi.MANAGER,
                WarmAlarmVibrationApi.EFFECT,
                -> {
                    vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
                }

                WarmAlarmVibrationApi.LEGACY -> {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, 0)
                }
            }
        }
    }

    override fun stop() {
        runCatching { activeVibrator?.cancel() }
        activeVibrator = null
    }

    @Suppress("DEPRECATION")
    private fun resolveVibrator(): Vibrator? =
        when (selectWarmAlarmVibrationApi(sdkInt)) {
            WarmAlarmVibrationApi.MANAGER -> {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            }

            WarmAlarmVibrationApi.EFFECT,
            WarmAlarmVibrationApi.LEGACY,
            -> {
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }
}
