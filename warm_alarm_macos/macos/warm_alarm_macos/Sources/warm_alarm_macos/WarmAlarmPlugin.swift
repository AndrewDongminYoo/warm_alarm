import FlutterMacOS
import Foundation

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
   public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger
    let instance = WarmAlarmPlugin()
    WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
    registrar.publish(instance)
  }

  func getCapabilities(completion: @escaping (Result<WarmAlarmCapabilitiesWire, Error>) -> Void) {
    completion(.success(macosCapabilities()))
  }

  func getPermissionState(completion: @escaping (Result<WarmAlarmPermissionStateWire, Error>) -> Void) {
    completion(.success(macosPermissionState()))
  }

  func getReadiness(completion: @escaping (Result<WarmAlarmReadinessWire, Error>) -> Void) {
    completion(.success(macosReadiness()))
  }

  func scheduleAlarm(
    schedule: WarmAlarmScheduleWire,
    completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void
  ) {
    completion(
      .success(
        WarmAlarmScheduleResultWire(
          alarmId: schedule.id,
          readiness: macosReadiness(),
          warning: WarmAlarmWarningWire(
            message: "Phase 1A macOS stub accepted the request without native alarm runtime behavior."
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

  private func macosCapabilities() -> WarmAlarmCapabilitiesWire {
    WarmAlarmCapabilitiesWire(
      exactScheduling: .unsupported,
      notificationScheduling: .supported,
      backgroundAudioPlayback: .limited,
      fullScreenPresentation: .unsupported,
      wakeCheck: .unsupported,
      liveActivity: .unsupported
    )
  }

  private func macosPermissionState() -> WarmAlarmPermissionStateWire {
    WarmAlarmPermissionStateWire(
      notificationsGranted: false,
      exactAlarmGranted: false,
      fullScreenIntentGranted: false
    )
  }

  private func macosReadiness() -> WarmAlarmReadinessWire {
    WarmAlarmReadinessWire(
      level: .limited,
      reasons: [.backgroundExecutionLimited]
    )
  }
}
