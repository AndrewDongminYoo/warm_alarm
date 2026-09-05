import AVFoundation
import Foundation
import UserNotifications

import Flutter

final class WarmAlarmConsumedOccurrenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "warm_alarm_consumed_occurrences"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load(alarmId: Int64) -> Int64? {
        (defaults.dictionary(forKey: key)?[String(alarmId)] as? NSNumber)?.int64Value
    }

    func save(alarmId: Int64, occurrenceMillis: Int64) {
        var values = defaults.dictionary(forKey: key) ?? [:]
        values[String(alarmId)] = occurrenceMillis
        defaults.set(values, forKey: key)
    }

    func clear(alarmId: Int64) {
        var values = defaults.dictionary(forKey: key) ?? [:]
        values.removeValue(forKey: String(alarmId))
        defaults.set(values, forKey: key)
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
    }
}

final class WarmAlarmForegroundOccurrenceTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var latestHandledOccurrenceMillisByAlarmId = [Int64: Int64]()
    private var latestConsumedOccurrenceMillisByAlarmId = [Int64: Int64]()
    private let consumedOccurrenceStore: WarmAlarmConsumedOccurrenceStore?

    init(consumedOccurrenceStore: WarmAlarmConsumedOccurrenceStore? = nil) {
        self.consumedOccurrenceStore = consumedOccurrenceStore
    }

    func shouldHandleAndMark(alarmId: Int64, occurrenceToken: String) -> Bool {
        handleIfAllowed(
            alarmId: alarmId,
            occurrenceToken: occurrenceToken,
            perform: {}
        )
    }

    func handleIfAllowed(
        alarmId: Int64,
        occurrenceToken: String,
        perform action: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remember(alarmId: alarmId, occurrenceToken: occurrenceToken) else { return false }
        action()
        return true
    }

    func clear(alarmId: Int64) {
        lock.lock()
        latestHandledOccurrenceMillisByAlarmId.removeValue(forKey: alarmId)
        latestConsumedOccurrenceMillisByAlarmId.removeValue(forKey: alarmId)
        consumedOccurrenceStore?.clear(alarmId: alarmId)
        lock.unlock()
    }

    @discardableResult
    func stop(
        alarmId: Int64,
        occurrenceToken: String,
        minimumOccurrenceMillis: Int64? = nil
    ) -> Bool {
        stop(
            alarmId: alarmId,
            occurrenceToken: occurrenceToken,
            minimumOccurrenceMillis: minimumOccurrenceMillis,
            perform: {}
        )
    }

    @discardableResult
    func stop(
        alarmId: Int64,
        occurrenceToken: String,
        minimumOccurrenceMillis: Int64? = nil,
        perform action: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let occurrenceMillis = occurrenceMillis(from: occurrenceToken),
              latestHandledOccurrenceMillisByAlarmId[alarmId].map({ occurrenceMillis >= $0 }) ?? true,
              minimumOccurrenceMillis.map({ occurrenceMillis >= $0 }) ?? true else {
            return false
        }
        let consumedOccurrenceMillis = max(
            latestConsumedOccurrenceMillisByAlarmId[alarmId] ?? .min,
            consumedOccurrenceStore?.load(alarmId: alarmId) ?? .min
        )
        guard occurrenceMillis > consumedOccurrenceMillis else {
            return false
        }
        latestHandledOccurrenceMillisByAlarmId[alarmId] = occurrenceMillis
        latestConsumedOccurrenceMillisByAlarmId[alarmId] = occurrenceMillis
        consumedOccurrenceStore?.save(alarmId: alarmId, occurrenceMillis: occurrenceMillis)
        action()
        return true
    }

    private func remember(alarmId: Int64, occurrenceToken: String) -> Bool {
        guard let occurrenceMillis = occurrenceMillis(from: occurrenceToken) else {
            return false
        }
        let consumedOccurrenceMillis = max(
            latestConsumedOccurrenceMillisByAlarmId[alarmId] ?? .min,
            consumedOccurrenceStore?.load(alarmId: alarmId) ?? .min
        )
        guard occurrenceMillis > consumedOccurrenceMillis,
              latestHandledOccurrenceMillisByAlarmId[alarmId].map({ occurrenceMillis > $0 }) ?? true else {
            return false
        }
        latestHandledOccurrenceMillisByAlarmId[alarmId] = occurrenceMillis
        return true
    }

    private func occurrenceMillis(from occurrenceToken: String) -> Int64? {
        Int64(occurrenceToken.split(separator: "#").last ?? "")
    }

    func clearAll() {
        lock.lock()
        latestHandledOccurrenceMillisByAlarmId.removeAll()
        latestConsumedOccurrenceMillisByAlarmId.removeAll()
        consumedOccurrenceStore?.clearAll()
        lock.unlock()
    }
}

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"

    private let eventsApi: WarmAlarmEventsApiProtocol
    private let notificationMutationQueue: WarmAlarmMutationQueue
    private var audioPlayer: AVAudioPlayer?
    private(set) var currentlyPlayingAlarmId: Int64?
    private(set) var currentlyPlayingOccurrenceToken: String?
    private let foregroundOccurrenceTracker = WarmAlarmForegroundOccurrenceTracker(
        consumedOccurrenceStore: WarmAlarmConsumedOccurrenceStore()
    )
    private var fadeWorkItems: [DispatchWorkItem] = []
    private var volumeEnforcerTimer: Timer?

    init(
        eventsApi: WarmAlarmEventsApiProtocol,
        notificationMutationQueue: WarmAlarmMutationQueue,
        currentlyPlayingAlarmId: Int64? = nil,
        currentlyPlayingOccurrenceToken: String? = nil
    ) {
        self.eventsApi = eventsApi
        self.notificationMutationQueue = notificationMutationQueue
        self.currentlyPlayingAlarmId = currentlyPlayingAlarmId
        self.currentlyPlayingOccurrenceToken = currentlyPlayingOccurrenceToken
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
        guard schedule.map({ WarmAlarmPlugin.notificationContent($0, matches: notification.request.content) })
            ?? true else {
            completionHandler([])
            return
        }
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: notification.request.content,
            identifier: notification.request.identifier,
            alarmId: alarmId,
            deliveredAtMillis: Int64(notification.date.timeIntervalSince1970 * 1_000),
            schedule: schedule
        )
        guard foregroundOccurrenceTracker.handleIfAllowed(
            alarmId: alarmId,
            occurrenceToken: occurrenceToken,
            perform: {
            startAudio(alarmId: alarmId, occurrenceToken: occurrenceToken, for: schedule)
            emitEvent(WarmAlarmEventWire(
                alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule?.payload))
            }
        ) else {
            completionHandler([])
            return
        }
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
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: response.notification.request.content,
            identifier: deliveredIdentifier,
            alarmId: alarmId,
            deliveredAtMillis: Int64(response.notification.date.timeIntervalSince1970 * 1_000),
            schedule: schedule
        )
        switch response.actionIdentifier {
        case Self.stopActionIdentifier:
            enqueueNotificationAction({ [weak self] in
                self?.handleStop(
                    alarmId: alarmId,
                    occurrenceToken: occurrenceToken,
                    deliveredIdentifier: deliveredIdentifier,
                    content: response.notification.request.content
                )
            }, completionHandler: completionHandler)
        case Self.snoozeActionIdentifier:
            notificationMutationQueue.enqueueOnMain { [weak self] finish in
                guard let self else {
                    completionHandler()
                    finish()
                    return
                }
                self.handleSnooze(
                    alarmId: alarmId,
                    occurrenceToken: occurrenceToken,
                    deliveredIdentifier: deliveredIdentifier,
                    content: response.notification.request.content
                ) {
                    completionHandler()
                    finish()
                }
            }
        case UNNotificationDefaultActionIdentifier:
            guard schedule.map({ WarmAlarmPlugin.notificationContent($0, matches: response.notification.request.content) })
                ?? true else {
                completionHandler()
                return
            }
            _ = foregroundOccurrenceTracker.handleIfAllowed(
                alarmId: alarmId,
                occurrenceToken: occurrenceToken,
                perform: {
                    startAudio(alarmId: alarmId, occurrenceToken: occurrenceToken, for: schedule)
                    emitEvent(WarmAlarmEventWire(
                        alarmId: alarmId,
                        type: .fired,
                        occurredAtMillis: nowMillis(),
                        payload: schedule?.payload
                    ))
                }
            )
            completionHandler()
        default:
            completionHandler()
        }
    }

    // MARK: - Actions

    func handleStop(
        alarmId: Int64,
        occurrenceToken: String,
        deliveredIdentifier: String? = nil,
        content: UNNotificationContent? = nil
    ) {
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        let actionLowerBound = schedule.flatMap {
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: $0,
                content: content,
                nowMillis: nowMillis()
            )
        }
        guard foregroundOccurrenceTracker.stop(
            alarmId: alarmId,
            occurrenceToken: occurrenceToken,
            minimumOccurrenceMillis: actionLowerBound,
            perform: stopAudio
        ) else {
            stopAudioIfPlaying(alarmId: alarmId, occurrenceToken: occurrenceToken)
            return
        }
        let preservesActiveSnooze = schedule?.activeSnoozeUntilMillis.map { $0 > nowMillis() } == true
            && content.map { content in
                schedule.map { WarmAlarmPlugin.isFloatingRecurringOccurrence(for: $0, content: content) } == true
            } == true
        if !preservesActiveSnooze {
            removePendingFallbackRequests(for: alarmId)
        }
        // Dismiss ends only this occurrence for a recurring alarm; the repeating
        // triggers stay armed, so keep the stored schedule. cancelAlarm tears down
        // the series.
        let isRecurring = !(schedule?.recurrenceWeekdays?.isEmpty ?? true)
        if isRecurring, let schedule {
            WarmAlarmStore.shared.save(preservesActiveSnooze ? schedule : schedule.clearingFallbackAnchor())
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
        occurrenceToken: String,
        deliveredIdentifier: String? = nil,
        content: UNNotificationContent? = nil,
        completion: @escaping () -> Void
    ) {
        let schedule = WarmAlarmStore.shared.load(id: alarmId)
        let actionLowerBound = schedule.flatMap {
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: $0,
                content: content,
                nowMillis: nowMillis()
            )
        }
        guard foregroundOccurrenceTracker.stop(
            alarmId: alarmId,
            occurrenceToken: occurrenceToken,
            minimumOccurrenceMillis: actionLowerBound,
            perform: stopAudio
        ) else {
            stopAudioIfPlaying(alarmId: alarmId, occurrenceToken: occurrenceToken)
            completion()
            return
        }
        removePendingFallbackRequests(for: alarmId)
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
        notificationMutationQueue.enqueueOnMain { finish in
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

    private func startAudio(
        alarmId: Int64,
        occurrenceToken: String,
        for schedule: WarmAlarmScheduleData?
    ) {
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
            currentlyPlayingOccurrenceToken = occurrenceToken
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
        currentlyPlayingOccurrenceToken = nil
        deactivateAudioSession()
    }

    private func stopAudioIfPlaying(alarmId: Int64, occurrenceToken: String) {
        guard currentlyPlayingAlarmId == alarmId,
              currentlyPlayingOccurrenceToken == occurrenceToken else { return }
        stopAudio()
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
        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {
                WarmAlarmStore.shared.save(updated)
            },
            register: { registrationCompletion in
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
                        registrationCompletion(PigeonError(
                            code: "pending-notification-limit",
                            message: "iOS has no notification slot for the snoozed alarm.",
                            details: nil
                        ))
                        return
                    }
                    WarmAlarmPlugin.addRequestsAtomically(
                        selection.requests,
                        center: center,
                        completion: registrationCompletion
                    )
                }
            },
            rollback: {
                let isRecurring = !(existing.recurrenceWeekdays?.isEmpty ?? true)
                if isRecurring {
                    WarmAlarmStore.shared.save(existing.clearingFallbackAnchor())
                } else {
                    WarmAlarmStore.shared.remove(id: existing.id)
                }
            },
            completion: completion
        )
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
