import AVFoundation
import Foundation
import UserNotifications

import FlutterMacOS

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"

    private let eventsApi: WarmAlarmEventsApi
    private var audioPlayer: AVAudioPlayer?
    private(set) var currentlyPlayingAlarmId: Int64?
    private var fadeWorkItems: [DispatchWorkItem] = []
    private var volumeEnforcerTimer: Timer?

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
            completionHandler([.alert, .sound])
            return
        }
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        startAudio(alarmId: alarmId, for: schedule)
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule?.payload))
        completionHandler([.alert])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let alarmIdString = response.notification.request.content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else { return }

        let deliveredIdentifier = response.notification.request.identifier
        switch response.actionIdentifier {
        case Self.stopActionIdentifier:
            handleStop(alarmId: alarmId, deliveredIdentifier: deliveredIdentifier)
        case Self.snoozeActionIdentifier:
            handleSnooze(alarmId: alarmId, deliveredIdentifier: deliveredIdentifier)
        case UNNotificationDefaultActionIdentifier:
            let schedule = WarmAlarmStore.shared.load(id: alarmId)
            startAudio(alarmId: alarmId, for: schedule)
            emitEvent(WarmAlarmEventWire(
                alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule?.payload))
        default:
            break
        }
    }

    // MARK: - Actions

    func handleStop(alarmId: Int64, deliveredIdentifier: String? = nil) {
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        stopAudio()
        // Dismiss ends only this occurrence for a recurring alarm; the repeating
        // triggers stay armed, so keep the stored schedule. cancelAlarm tears down
        // the series.
        let isRecurring = !(schedule?.recurrenceWeekdays?.isEmpty ?? true)
        if !isRecurring {
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        if schedule?.keepNotificationAfterAlarmEnds != true {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [deliveredIdentifier ?? String(alarmId)])
        }
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .stopped, occurredAtMillis: nowMillis(), payload: schedule?.payload))
    }

    func handleSnooze(alarmId: Int64, deliveredIdentifier: String? = nil) {
        stopAudio()
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        if schedule?.keepNotificationAfterAlarmEnds != true {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [deliveredIdentifier ?? String(alarmId)])
        }
        let snoozeDurationMillis = schedule?.snoozeDurationMillis ?? (5 * 60 * 1000)
        let fireAt = nowMillis() + snoozeDurationMillis
        reschedule(alarmId: alarmId, fireAtMillis: fireAt, existing: schedule)
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId,
            type: .snoozed,
            occurredAtMillis: nowMillis(),
            snoozeDurationMillis: snoozeDurationMillis,
            payload: schedule?.payload
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

    private func startAudio(alarmId: Int64, for schedule: WarmAlarmScheduleData?) {
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
            let steps = schedule?.fadeSteps
            if let first = steps?.first, first.timeMillis == 0 {
                p.volume = max(0.0, min(1.0, Float(first.volume)))
            } else if let v = schedule?.volume {
                p.volume = max(0.0, min(1.0, Float(v)))
            } else {
                p.volume = 1.0
            }
            p.numberOfLoops = (schedule?.loop ?? true) ? -1 : 0
            p.play()
            audioPlayer = p
            currentlyPlayingAlarmId = alarmId
            if let steps = steps { applyFadeSteps(steps, to: p) }
            if schedule?.volumeEnforced == true { startVolumeEnforcer(for: p) }
        }
    }

    private func applyFadeSteps(_ steps: [FadeStep], to player: AVAudioPlayer) {
        for step in steps {
            guard step.timeMillis > 0 else { continue }
            let vol = max(0.0, min(1.0, Float(step.volume)))
            let item = DispatchWorkItem { [weak player] in player?.volume = vol }
            fadeWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step.timeMillis) / 1000.0, execute: item)
        }
    }

    private func startVolumeEnforcer(for player: AVAudioPlayer) {
        volumeEnforcerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak player] _ in
            player?.volume = 1.0
        }
    }

    private func stopAudio() {
        fadeWorkItems.forEach { $0.cancel() }
        fadeWorkItems = []
        volumeEnforcerTimer?.invalidate()
        volumeEnforcerTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingAlarmId = nil
        deactivateAudioSession()
    }

    private func configureAudioSession() {}

    private func deactivateAudioSession() {}

    // MARK: - Reschedule (snooze)

    private func reschedule(alarmId: Int64, fireAtMillis: Int64, existing: WarmAlarmScheduleData?) {
        guard let existing = existing else { return }
        let updated = WarmAlarmScheduleData(
            id: existing.id, scheduledAtMillis: fireAtMillis,
            notificationTitle: existing.notificationTitle, notificationBody: existing.notificationBody,
            stopActionTitle: existing.stopActionTitle, snoozeActionTitle: existing.snoozeActionTitle,
            filePath: existing.filePath, assetPath: existing.assetPath,
            loop: existing.loop, volume: existing.volume, vibrate: existing.vibrate,
            fadeInDurationMillis: existing.fadeInDurationMillis,
            recurrenceWeekdays: existing.recurrenceWeekdays,
            snoozeDurationMillis: existing.snoozeDurationMillis,
            payload: existing.payload,
            volumeEnforced: existing.volumeEnforced,
            fadeSteps: existing.fadeSteps,
            keepNotificationAfterAlarmEnds: existing.keepNotificationAfterAlarmEnds
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
