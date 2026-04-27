import AVFoundation
import Foundation
import UserNotifications

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"

    private let eventsApi: WarmAlarmEventsApi
    private var audioPlayer: AVAudioPlayer?

    init(eventsApi: WarmAlarmEventsApi) {
        self.eventsApi = eventsApi
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let alarmIdString = notification.request.content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else {
            completionHandler([.banner, .sound])
            return
        }
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        startAudio(for: schedule)
        emitEvent(WarmAlarmEventWire(alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis()))
        completionHandler([.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let alarmIdString = response.notification.request.content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else { return }

        switch response.actionIdentifier {
        case Self.stopActionIdentifier:
            handleStop(alarmId: alarmId)
        case Self.snoozeActionIdentifier:
            handleSnooze(alarmId: alarmId)
        case UNNotificationDefaultActionIdentifier:
            let schedule = WarmAlarmStore.shared.load(id: alarmId)
            startAudio(for: schedule)
            emitEvent(WarmAlarmEventWire(alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis()))
        default:
            break
        }
    }

    // MARK: - Actions

    func handleStop(alarmId: Int64) {
        stopAudio()
        WarmAlarmStore.shared.remove(id: alarmId)
        emitEvent(WarmAlarmEventWire(alarmId: alarmId, type: .stopped, occurredAtMillis: nowMillis()))
    }

    func handleSnooze(alarmId: Int64) {
        stopAudio()
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        let snoozeDurationMillis = schedule?.snoozeDurationMillis ?? (5 * 60 * 1000)
        let fireAt = nowMillis() + snoozeDurationMillis
        reschedule(alarmId: alarmId, fireAtMillis: fireAt, existing: schedule)
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId,
            type: .snoozed,
            occurredAtMillis: nowMillis(),
            snoozeDurationMillis: snoozeDurationMillis
        ))
    }

    // MARK: - Called by WarmAlarmPlugin

    func emitScheduled(alarmId: Int64) {
        emitEvent(WarmAlarmEventWire(alarmId: alarmId, type: .scheduled, occurredAtMillis: nowMillis()))
    }

    func emitFailure(alarmId: Int64, message: String) {
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId,
            type: .failed,
            occurredAtMillis: nowMillis(),
            failure: WarmAlarmFailureWire(code: .schedulingFailed, message: message)
        ))
    }

    func makeContent(from schedule: WarmAlarmScheduleData) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = schedule.notificationTitle
        content.body = schedule.notificationBody
        content.sound = UNNotificationSound.default
        content.userInfo = ["alarmId": String(schedule.id)]
        content.categoryIdentifier = Self.categoryIdentifier
        return content
    }

    // MARK: - Category registration

    static func registerCategories() {
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier, title: "Stop", options: .destructive)
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier, title: "Snooze", options: [])
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [stop, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Audio

    private func startAudio(for schedule: WarmAlarmScheduleData?) {
        configureAudioSession()
        let player: AVAudioPlayer?
        if let path = schedule?.filePath, !path.isEmpty {
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        } else if let asset = schedule?.assetPath, !asset.isEmpty,
                  let url = Bundle.main.url(forResource: "flutter_assets/\(asset)", withExtension: nil) {
            player = try? AVAudioPlayer(contentsOf: url)
        } else {
            player = nil
        }
        if let p = player {
            p.numberOfLoops = (schedule?.loop ?? true) ? -1 : 0
            p.play()
            audioPlayer = p
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        deactivateAudioSession()
    }

    private func configureAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Reschedule (snooze)

    private func reschedule(alarmId: Int64, fireAtMillis: Int64, existing: WarmAlarmScheduleData?) {
        guard let existing = existing else { return }
        let updated = WarmAlarmScheduleData(
            id: existing.id, scheduledAtMillis: fireAtMillis,
            notificationTitle: existing.notificationTitle, notificationBody: existing.notificationBody,
            stopActionTitle: existing.stopActionTitle, snoozeActionTitle: existing.snoozeActionTitle,
            filePath: existing.filePath, assetPath: existing.assetPath,
            loop: existing.loop, snoozeDurationMillis: existing.snoozeDurationMillis
        )
        WarmAlarmStore.shared.save(updated)
        let content = makeContent(from: updated)
        let delay = max(1.0, Double(fireAtMillis - nowMillis()) / 1000.0)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: String(alarmId), content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Helpers

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func emitEvent(_ event: WarmAlarmEventWire) {
        eventsApi.emitEvent(event: event) { _ in }
    }
}
