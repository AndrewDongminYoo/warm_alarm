import AVFoundation
import Foundation
import UserNotifications

import FlutterMacOS

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"

    private let eventQueue: WarmAlarmEventQueue
    private let audioPlayerFactory: (URL) throws -> AVAudioPlayer
    private let playbackLock: NSRecursiveLock
    private var activePlayer: AVAudioPlayer?
    private var activeAlarmId: Int64?
    private var fadeWorkItems: [DispatchWorkItem] = []
    private var volumeEnforcerTimer: Timer?

    var audioPlayer: AVAudioPlayer? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        return activePlayer
    }

    var currentlyPlayingAlarmId: Int64? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        return activeAlarmId
    }

    init(
        eventsApi: WarmAlarmEventsApi,
        eventQueue: WarmAlarmEventQueue? = nil,
        playbackLock: NSRecursiveLock = NSRecursiveLock(),
        audioPlayerFactory: @escaping (URL) throws -> AVAudioPlayer = { try AVAudioPlayer(contentsOf: $0) }
    ) {
        self.playbackLock = playbackLock
        self.audioPlayerFactory = audioPlayerFactory
        self.eventQueue = eventQueue ?? WarmAlarmEventQueue { event, completion in
            let emit = {
                eventsApi.emitEvent(event: event) { result in
                    switch result {
                    case .success:
                        completion(true)
                    case .failure:
                        completion(false)
                    }
                }
            }
            if Thread.isMainThread {
                emit()
            } else {
                DispatchQueue.main.async(execute: emit)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(handleForegroundDelivery(content: notification.request.content))
    }

    func handleForegroundDelivery(content: UNNotificationContent) -> UNNotificationPresentationOptions {
        guard content.categoryIdentifier == Self.categoryIdentifier else { return [.alert, .sound] }
        guard let alarmIdString = content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else {
            return [.alert, .sound]
        }
        guard let schedule = startForegroundAudio(alarmId: alarmId, content: content) else { return [] }
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule.payload))
        let source = WarmAlarmAudioSource.select(filePath: schedule.filePath, assetPath: schedule.assetPath)
        return source == .none ? [.alert, .sound] : [.alert]
    }

    private func startForegroundAudio(alarmId: Int64, content: UNNotificationContent) -> WarmAlarmScheduleData? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard let schedule = WarmAlarmStore.shared.load(id: alarmId),
              content.userInfo["occurrenceSeriesToken"] as? String == schedule.occurrenceSeriesToken else { return nil }
        startAudio(alarmId: alarmId, for: schedule)
        return schedule
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

    func stopIfPlaying(alarmId: Int64) {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard activeAlarmId == alarmId else { return }
        stopAudio()
    }

    func stopAllIfPlaying() {
        stopAudio()
    }

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
        if let token = schedule.occurrenceSeriesToken {
            content.userInfo["occurrenceSeriesToken"] = token
        }
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
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard let schedule,
              let storedSchedule = WarmAlarmStore.shared.load(id: alarmId),
              storedSchedule.occurrenceSeriesToken == schedule.occurrenceSeriesToken else { return }
        configureAudioSession()
        let player: AVAudioPlayer?
        switch WarmAlarmAudioSource.select(filePath: schedule.filePath, assetPath: schedule.assetPath) {
        case let .file(path):
            player = try? audioPlayerFactory(URL(fileURLWithPath: path))
        case let .asset(asset):
            if let url = WarmAlarmAudioSource.assetURL(for: asset) {
                player = try? audioPlayerFactory(url)
            } else {
                player = nil
            }
        case .none:
            player = nil
        }
        if let p = player {
            stopAudio()
            let steps = schedule.fadeSteps
            if let first = steps?.first, first.timeMillis == 0 {
                p.volume = max(0.0, min(1.0, Float(first.volume)))
            } else if let v = schedule.volume {
                p.volume = max(0.0, min(1.0, Float(v)))
            } else {
                p.volume = 1.0
            }
            p.numberOfLoops = schedule.loop ? -1 : 0
            p.play()
            activePlayer = p
            activeAlarmId = alarmId
            if let steps = steps { applyFadeSteps(steps, to: p) }
            if schedule.volumeEnforced == true { startVolumeEnforcer(for: p) }
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
        playbackLock.lock()
        defer { playbackLock.unlock() }
        fadeWorkItems.forEach { $0.cancel() }
        fadeWorkItems = []
        volumeEnforcerTimer?.invalidate()
        volumeEnforcerTimer = nil
        activePlayer?.stop()
        activePlayer = nil
        activeAlarmId = nil
        deactivateAudioSession()
    }

    private func configureAudioSession() {}

    private func deactivateAudioSession() {}

    // MARK: - Reschedule (snooze)

    private func reschedule(alarmId: Int64, fireAtMillis: Int64, existing: WarmAlarmScheduleData?) {
        guard let existing = existing else { return }
        let updated = existing.withActiveSnooze(untilMillis: fireAtMillis)
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
        eventQueue.enqueue(event)
    }

    func drainEvents() {
        eventQueue.drain()
    }
}
