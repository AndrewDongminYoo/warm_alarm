package com.andrew.alarm

import io.flutter.embedding.engine.plugins.FlutterPlugin

class WarmAlarmPlugin :
    FlutterPlugin,
    WarmAlarmApi {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WarmAlarmApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WarmAlarmApi.setUp(binding.binaryMessenger, null)
    }

    override fun getCapabilities(callback: (Result<WarmAlarmCapabilitiesWire>) -> Unit) {
        callback(Result.success(androidCapabilities()))
    }

    override fun getPermissionState(callback: (Result<WarmAlarmPermissionStateWire>) -> Unit) {
        callback(Result.success(androidPermissionState()))
    }

    override fun getReadiness(callback: (Result<WarmAlarmReadinessWire>) -> Unit) {
        callback(Result.success(androidReadiness()))
    }

    override fun scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        callback: (Result<WarmAlarmScheduleResultWire>) -> Unit,
    ) {
        callback(
            Result.success(
                WarmAlarmScheduleResultWire(
                    alarmId = schedule.id,
                    readiness = androidReadiness(),
                    warning =
                        WarmAlarmWarningWire(
                            message = "Phase 1A Android stub accepted the request without scheduling a native alarm.",
                        ),
                ),
            ),
        )
    }

    override fun cancelAlarm(
        id: Long,
        callback: (Result<Unit>) -> Unit,
    ) {
        callback(Result.success(Unit))
    }

    override fun cancelAllAlarms(callback: (Result<Unit>) -> Unit) {
        callback(Result.success(Unit))
    }

    override fun getScheduledAlarms(callback: (Result<List<WarmAlarmSnapshotWire>>) -> Unit) {
        callback(Result.success(emptyList()))
    }

    private fun androidCapabilities() =
        WarmAlarmCapabilitiesWire(
            exactScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
            notificationScheduling = WarmAlarmSupportStatusWire.SUPPORTED,
            backgroundAudioPlayback = WarmAlarmSupportStatusWire.LIMITED,
            fullScreenPresentation = WarmAlarmSupportStatusWire.SUPPORTED,
            wakeCheck = WarmAlarmSupportStatusWire.UNSUPPORTED,
            liveActivity = WarmAlarmSupportStatusWire.UNSUPPORTED,
        )

    private fun androidPermissionState() =
        WarmAlarmPermissionStateWire(
            notificationsGranted = false,
            exactAlarmGranted = false,
            fullScreenIntentGranted = false,
        )

    private fun androidReadiness() =
        WarmAlarmReadinessWire(
            level = WarmAlarmReadinessLevelWire.BLOCKED,
            reasons = listOf(WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED),
        )
}
