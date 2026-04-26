import Flutter

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger()
    let instance = WarmAlarmPlugin()
    WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
    registrar.publish(instance)
  }

  func getCapabilities(completion: @escaping (Result<WarmAlarmCapabilitiesWire, Error>) -> Void) {
    completion(.success(iosCapabilities()))
  }

  func getPermissionState(completion: @escaping (Result<WarmAlarmPermissionStateWire, Error>) -> Void) {
    completion(.success(iosPermissionState()))
  }

  func getReadiness(completion: @escaping (Result<WarmAlarmReadinessWire, Error>) -> Void) {
    completion(.success(iosReadiness()))
  }

  func scheduleAlarm(
    schedule: WarmAlarmScheduleWire,
    completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void
  ) {
    completion(
      .success(
        WarmAlarmScheduleResultWire(
          alarmId: schedule.id,
          readiness: iosReadiness(),
          warning: WarmAlarmWarningWire(
            message: "Phase 1A iOS stub accepted the request without native alarm runtime behavior."
          )
        )
      )
    )
  }

  func cancelAlarm(id: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.success(()))
  }

  func cancelAllAlarms(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.success(()))
  }

  func getScheduledAlarms(completion: @escaping (Result<[WarmAlarmSnapshotWire], Error>) -> Void) {
    completion(.success([]))
  }

  private func iosCapabilities() -> WarmAlarmCapabilitiesWire {
    WarmAlarmCapabilitiesWire(
      exactScheduling: .limited,
      notificationScheduling: .supported,
      backgroundAudioPlayback: .limited,
      fullScreenPresentation: .unsupported,
      wakeCheck: .unsupported,
      liveActivity: .supported
    )
  }

  private func iosPermissionState() -> WarmAlarmPermissionStateWire {
    WarmAlarmPermissionStateWire(
      notificationsGranted: false,
      exactAlarmGranted: false,
      fullScreenIntentGranted: false
    )
  }

  private func iosReadiness() -> WarmAlarmReadinessWire {
    WarmAlarmReadinessWire(
      level: .limited,
      reasons: [.backgroundExecutionLimited]
    )
  }
}
