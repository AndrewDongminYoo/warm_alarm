import AVFoundation
import Foundation
import UserNotifications

import Flutter

final class WarmAlarmForegroundOccurrenceTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var handledAlarmIds = Set<Int64>()

    func shouldHandleAndMark(alarmId: Int64, isFallback: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isFallback, handledAlarmIds.contains(alarmId) {
            return false
        }
        handledAlarmIds.insert(alarmId)
        return true
    }

    func mark(alarmId: Int64) {
        lock.lock()
        handledAlarmIds.insert(alarmId)
        lock.unlock()
    }

    func clear(alarmId: Int64) {
        lock.lock()
        handledAlarmIds.remove(alarmId)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        handledAlarmIds.removeAll()
        lock.unlock()
    }
}

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"

    private let eventsApi: WarmAlarmEventsApi
    private let notificationMutationQueue: WarmAlarmMutationQueue
    private var audioPlayer: AVAudioPlayer?
    private(set) var currentlyPlayingAlarmId: Int64?
    private let foregroundOccurrenceTracker = WarmAlarmForegroundOccurrenceTracker()
    private var fadeWorkItems: [DispatchWorkItem] = []
    private var volumeEnforcerTimer: Timer?

    init(
        eventsApi: WarmAlarmEventsApi,
        notificationMutationQueue: WarmAlarmMutationQueue
    ) {
        self.eventsApi = eventsApi
        self.notificationMutationQueue = notificationMutationQueue
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
        let isFallback = WarmAlarmPlugin.isFallbackIdentifier(notification.request.identifier, for: alarmId)
        guard foregroundOccurrenceTracker.shouldHandleAndMark(alarmId: alarmId, isFallback: isFallback) else {
            completionHandler([])
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
        guard let alarmIdString = response.notification.request.content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else {
            completionHandler()
            return
        }

        let deliveredIdentifier = response.notification.request.identifier
        switch response.actionIdentifier {
        case Self.stopActionIdentifier:
            enqueueNotificationAction({ [weak self] in
                self?.handleStop(alarmId: alarmId, deliveredIdentifier: deliveredIdentifier)
            }, completionHandler: completionHandler)
        case Self.snoozeActionIdentifier:
            notificationMutationQueue.enqueue { [weak self] finish in
                guard let self else {
                    completionHandler()
                    finish()
                    return
                }
                self.handleSnooze(
                    alarmId: alarmId,
                    deliveredIdentifier: deliveredIdentifier
                ) {
                    completionHandler()
                    finish()
                }
            }
        case UNNotificationDefaultActionIdentifier:
            foregroundOccurrenceTracker.mark(alarmId: alarmId)
            let schedule = WarmAlarmStore.shared.load(id: alarmId)
            startAudio(alarmId: alarmId, for: schedule)
            emitEvent(WarmAlarmEventWire(
                alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule?.payload))
            completionHandler()
        default:
            completionHandler()
        }
    }

    // MARK: - Actions

    func handleStop(alarmId: Int64, deliveredIdentifier: String? = nil) {
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        foregroundOccurrenceTracker.clear(alarmId: alarmId)
        stopAudio()
        removePendingFallbackRequests(for: alarmId)
        // Dismiss ends only this occurrence for a recurring alarm; the repeating
        // triggers stay armed, so keep the stored schedule. cancelAlarm tears down
        // the series.
        let isRecurring = !(schedule?.recurrenceWeekdays?.isEmpty ?? true)
        if isRecurring, let schedule {
            WarmAlarmStore.shared.save(schedule.clearingFallbackAnchor())
        } else {
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        if schedule?.keepNotificationAfterAlarmEnds != true {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: Self.deliveredIdentifiersToRemove(
                    alarmId: alarmId,
                    recurrenceWeekdays: schedule?.recurrenceWeekdays,
                    deliveredIdentifier: deliveredIdentifier
                )
            )
        }
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .stopped, occurredAtMillis: nowMillis(), payload: schedule?.payload))
    }

    func handleSnooze(
        alarmId: Int64,
        deliveredIdentifier: String? = nil,
        completion: @escaping () -> Void
    ) {
        foregroundOccurrenceTracker.clear(alarmId: alarmId)
        stopAudio()
        removePendingFallbackRequests(for: alarmId)
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        if schedule?.keepNotificationAfterAlarmEnds != true {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: Self.deliveredIdentifiersToRemove(
                    alarmId: alarmId,
                    recurrenceWeekdays: schedule?.recurrenceWeekdays,
                    deliveredIdentifier: deliveredIdentifier
                )
            )
        }
        let snoozeDurationMillis = schedule?.snoozeDurationMillis ?? (5 * 60 * 1000)
        let fireAt = nowMillis() + snoozeDurationMillis
        reschedule(
            fireAtMillis: fireAt,
            existing: schedule
        ) { [weak self] error in
            guard let self else {
                completion()
                return
            }
            if let error {
                let isRecurring = !(schedule?.recurrenceWeekdays?.isEmpty ?? true)
                if isRecurring, let schedule {
                    WarmAlarmStore.shared.save(schedule.clearingFallbackAnchor())
                } else {
                    WarmAlarmStore.shared.remove(id: alarmId)
                }
                self.emitFailure(alarmId: alarmId, message: error.localizedDescription)
            } else {
                self.emitEvent(WarmAlarmEventWire(
                    alarmId: alarmId,
                    type: .snoozed,
                    occurredAtMillis: self.nowMillis(),
                    snoozeDurationMillis: snoozeDurationMillis,
                    payload: schedule?.payload
                ))
            }
            completion()
        }
    }

    // MARK: - Called by WarmAlarmPlugin

    func clearHandledForegroundOccurrence(alarmId: Int64) {
        foregroundOccurrenceTracker.clear(alarmId: alarmId)
    }

    static func deliveredIdentifiersToRemove(
        alarmId: Int64,
        recurrenceWeekdays: [Int64]?,
        deliveredIdentifier: String?
    ) -> [String] {
        var identifiers = WarmAlarmPlugin.requestIdentifiers(
            for: alarmId,
            recurrenceWeekdays: recurrenceWeekdays
        )
        if let deliveredIdentifier, !identifiers.contains(deliveredIdentifier) {
            identifiers.append(deliveredIdentifier)
        }
        return identifiers
    }

    func stopIfPlaying(alarmId: Int64) {
        foregroundOccurrenceTracker.clear(alarmId: alarmId)
        guard currentlyPlayingAlarmId == alarmId else { return }
        stopAudio()
    }

    func stopAllIfPlaying() {
        foregroundOccurrenceTracker.clearAll()
        guard currentlyPlayingAlarmId != nil else { return }
        stopAudio()
    }

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
        // Use bundled alarm sound so the notification is audible when device is locked.
        // Falls back to default if the file is absent (e.g. simulator builds without the bundle).
        if Bundle.main.url(forResource: "alarm_ring", withExtension: "caf") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm_ring.caf"))
        } else {
            content.sound = .default
        }
        content.userInfo = ["alarmId": String(schedule.id)]
        content.categoryIdentifier = Self.categoryIdentifier
        return content
    }

    private func enqueueNotificationAction(
        _ action: @escaping () -> Void,
        completionHandler: @escaping () -> Void
    ) {
        notificationMutationQueue.enqueue { finish in
            action()
            completionHandler()
            finish()
        }
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

    // Flutter assets live in App.framework (not Runner.app directly) in both debug and release builds.
    private func flutterAssetURL(for asset: String) -> URL? {
        let appFramework = Bundle.main.bundleURL
            .appendingPathComponent("Frameworks/App.framework/flutter_assets")
            .appendingPathComponent(asset)
        if FileManager.default.fileExists(atPath: appFramework.path) { return appFramework }
        // Fallback for older / simulator build layouts.
        return Bundle.main.url(forResource: "flutter_assets/\(asset)", withExtension: nil)
    }

    private func startAudio(alarmId: Int64, for schedule: WarmAlarmScheduleData?) {
        configureAudioSession()
        let player: AVAudioPlayer?
        if let path = schedule?.filePath, !path.isEmpty {
            player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        } else if let asset = schedule?.assetPath, !asset.isEmpty,
                  let url = flutterAssetURL(for: asset) {
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

    private func configureAudioSession() {
        #if os(iOS)
        // .mixWithOthers lets warm_alarm coexist with just_audio playing the voice message.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Reschedule (snooze)

    private func reschedule(
        fireAtMillis: Int64,
        existing: WarmAlarmScheduleData?,
        completion: @escaping (Error?) -> Void
    ) {
        guard let existing else {
            completion(PigeonError(
                code: "alarm-not-found",
                message: "The alarm schedule does not exist.",
                details: nil
            ))
            return
        }
        let updated = existing.withActiveSnooze(
            untilMillis: fireAtMillis,
            fallbackAnchorMillis: fireAtMillis
        )
        let content = makeContent(from: updated)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pendingRequests in
            let requests = WarmAlarmPlugin.makeSnoozeRequests(
                for: updated,
                fireAtMillis: fireAtMillis,
                nowMillis: self.nowMillis(),
                content: content
            )
            let pendingIdentifiers = Set(pendingRequests.map(\.identifier))
            guard let selection = WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
                requests,
                pendingIdentifiers: pendingIdentifiers
            ) else {
                completion(PigeonError(
                    code: "pending-notification-limit",
                    message: "iOS has no notification slot for the snoozed alarm.",
                    details: nil
                ))
                return
            }
            WarmAlarmPlugin.addRequestsAtomically(
                selection.requests,
                center: center
            ) { error in
                if error == nil {
                    WarmAlarmStore.shared.save(updated)
                }
                completion(error)
            }
        }
    }

    private func removePendingFallbackRequests(for alarmId: Int64) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: WarmAlarmPlugin.fallbackIdentifiers(for: alarmId))
    }

    // MARK: - Helpers

    private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func emitEvent(_ event: WarmAlarmEventWire) {
        eventsApi.emitEvent(event: event) { _ in }
    }
}
