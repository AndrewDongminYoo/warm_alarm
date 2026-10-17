import AVFoundation
import CryptoKit
import Foundation
import UserNotifications

import FlutterMacOS

final class WarmAlarmDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryIdentifier = "WARM_ALARM"
    static let stopActionIdentifier = "STOP"
    static let snoozeActionIdentifier = "SNOOZE"
    private static let categoryMutationQueue = WarmAlarmMutationQueue(label: "warm_alarm.categories")

    typealias CategoryRegistrar = ([UNNotificationContent], @escaping () -> Void) -> Void

    let notificationMutationQueue: WarmAlarmMutationQueue
    // Unit tests inject a no-op registrar; the real one needs an app bundle identity.
    let categoryRegistrar: CategoryRegistrar
    private let pendingNotificationReader: WarmAlarmPlugin.PendingNotificationReader
    private let notificationAdder: WarmAlarmPlugin.NotificationAdder
    private let playAudio: (AVAudioPlayer) -> Bool
    private let eventQueue: WarmAlarmEventQueue
    private let audioPlayerFactory: (URL) throws -> AVAudioPlayer
    private let playbackLock: NSRecursiveLock
    private var activePlayer: AVAudioPlayer?
    private var activeAlarmId: Int64?
    private var activeOccurrenceToken: String?
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
        notificationMutationQueue: WarmAlarmMutationQueue = WarmAlarmMutationQueue(label: "warm_alarm.notification_mutation"),
        pendingNotificationReader: @escaping WarmAlarmPlugin.PendingNotificationReader = { completion in
            UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: completion)
        },
        playbackLock: NSRecursiveLock = NSRecursiveLock(),
        audioPlayerFactory: @escaping (URL) throws -> AVAudioPlayer = { try AVAudioPlayer(contentsOf: $0) },
        playAudio: @escaping (AVAudioPlayer) -> Bool = { $0.play() },
        notificationAdder: @escaping WarmAlarmPlugin.NotificationAdder = { request, completion in
            UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
        },
        categoryRegistrar: @escaping CategoryRegistrar = { contents, completion in
            WarmAlarmDelegate.registerCategories(for: contents, completion: completion)
        }
    ) {
        self.playbackLock = playbackLock
        self.audioPlayerFactory = audioPlayerFactory
        self.notificationMutationQueue = notificationMutationQueue
        self.pendingNotificationReader = pendingNotificationReader
        self.categoryRegistrar = categoryRegistrar
        self.notificationAdder = { request, completion in
            categoryRegistrar([request.content]) { notificationAdder(request, completion) }
        }
        self.playAudio = playAudio
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
        completionHandler(handleForegroundDelivery(
            content: notification.request.content,
            identifier: notification.request.identifier,
            deliveredAtMillis: Int64(notification.date.timeIntervalSince1970 * 1_000)
        ))
    }

    func handleForegroundDelivery(
        content: UNNotificationContent,
        identifier: String? = nil,
        deliveredAtMillis: Int64 = 0
    ) -> UNNotificationPresentationOptions {
        guard Self.ownsCategory(content.categoryIdentifier) else { return [.alert, .sound] }
        guard let alarmIdString = content.userInfo["alarmId"] as? String,
              let alarmId = Int64(alarmIdString) else {
            return [.alert, .sound]
        }
        let occurrenceToken = Self.occurrenceToken(
            content: content, identifier: identifier ?? String(alarmId), deliveredAtMillis: deliveredAtMillis
        )
        guard let (schedule, didStartAudio) = startForegroundAudio(
            alarmId: alarmId, content: content, occurrenceToken: occurrenceToken,
            deliveredIdentifier: identifier ?? String(alarmId)
        ) else { return [] }
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .fired, occurredAtMillis: nowMillis(), payload: schedule.payload))
        return didStartAudio ? [.alert] : [.alert, .sound]
    }

    private func startForegroundAudio(
        alarmId: Int64, content: UNNotificationContent, occurrenceToken: String, deliveredIdentifier: String
    ) -> (WarmAlarmScheduleData, Bool)? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard let schedule = actionSchedule(
            alarmId: alarmId, content: content, occurrenceToken: occurrenceToken, deliveredIdentifier: deliveredIdentifier
        ) else {
            return nil
        }
        guard let didStartAudio = startAudio(alarmId: alarmId, occurrenceToken: occurrenceToken, for: schedule) else {
            return nil
        }
        return (schedule, didStartAudio)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            deliveredIdentifier: response.notification.request.identifier,
            content: response.notification.request.content,
            deliveredAtMillis: Int64(response.notification.date.timeIntervalSince1970 * 1_000),
            completion: completionHandler
        )
    }

    func handleNotificationResponse(
        actionIdentifier: String,
        deliveredIdentifier: String,
        content: UNNotificationContent,
        deliveredAtMillis: Int64,
        completion: @escaping () -> Void
    ) {
        guard [Self.stopActionIdentifier, Self.snoozeActionIdentifier, UNNotificationDefaultActionIdentifier]
            .contains(actionIdentifier) else {
            completion()
            return
        }
        notificationMutationQueue.enqueueOnMain { [weak self] finish in
            guard let self else {
                completion()
                finish()
                return
            }
            let completed = {
                completion()
                finish()
            }
            guard Self.ownsCategory(content.categoryIdentifier),
                  let rawId = content.userInfo["alarmId"] as? String,
                  let alarmId = Int64(rawId) else {
                completed()
                return
            }
            let token = Self.occurrenceToken(
                content: content, identifier: deliveredIdentifier, deliveredAtMillis: deliveredAtMillis
            )
            switch actionIdentifier {
            case Self.stopActionIdentifier:
                self.handleStop(alarmId: alarmId, deliveredIdentifier: deliveredIdentifier,
                                content: content, occurrenceToken: token)
                completed()
            case Self.snoozeActionIdentifier:
                self.handleSnooze(alarmId: alarmId, deliveredIdentifier: deliveredIdentifier,
                                  content: content, occurrenceToken: token, completion: completed)
            case UNNotificationDefaultActionIdentifier:
                _ = self.handleForegroundDelivery(content: content, identifier: deliveredIdentifier,
                                                  deliveredAtMillis: deliveredAtMillis)
                completed()
            default:
                completed()
            }
        }
    }

    static func occurrenceToken(content: UNNotificationContent, identifier: String, deliveredAtMillis: Int64) -> String {
        let series = content.userInfo["occurrenceSeriesToken"] as? String ?? "legacy"
        return "\(series)#\(identifier)#\(deliveredAtMillis)"
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

    func handleStop(
        alarmId: Int64, deliveredIdentifier: String? = nil,
        content: UNNotificationContent? = nil, occurrenceToken: String? = nil
    ) {
        guard let schedule = actionSchedule(
            alarmId: alarmId, content: content, occurrenceToken: occurrenceToken, deliveredIdentifier: deliveredIdentifier
        ) else { return }
        stopAudioIfPlaying(alarmId: alarmId, occurrenceToken: occurrenceToken)
        // Dismiss ends only this occurrence for a recurring alarm; the repeating
        // triggers stay armed, so keep the stored schedule. cancelAlarm tears down
        // the series.
        let isRecurring = !(schedule.recurrenceWeekdays?.isEmpty ?? true)
        if !isRecurring {
            WarmAlarmStore.shared.remove(id: alarmId)
        } else if let consumed = occurrenceToken.flatMap({ Int64($0.split(separator: "#").last ?? "") }) {
            // A retained notification of a stopped occurrence must not snooze or replay it later.
            WarmAlarmStore.shared.save(schedule.withConsumedOccurrence(consumed))
        }
        if schedule.keepNotificationAfterAlarmEnds != true {
            UNUserNotificationCenter.current().removeDeliveredNotifications(
                withIdentifiers: [deliveredIdentifier ?? String(alarmId)])
        }
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .stopped, occurredAtMillis: nowMillis(), payload: schedule.payload))
    }

    func handleSnooze(
        alarmId: Int64, deliveredIdentifier: String? = nil,
        content: UNNotificationContent? = nil, occurrenceToken: String? = nil,
        completion: @escaping () -> Void = {}
    ) {
        guard let schedule = actionSchedule(
            alarmId: alarmId, content: content, occurrenceToken: occurrenceToken, deliveredIdentifier: deliveredIdentifier
        ) else {
            completion()
            return
        }
        stopAudioIfPlaying(alarmId: alarmId, occurrenceToken: occurrenceToken)
        let snoozeDurationMillis = schedule.snoozeDurationMillis ?? (5 * 60 * 1000)
        let fireAt = nowMillis() + snoozeDurationMillis
        let consumedOccurrence = occurrenceToken.flatMap { Int64($0.split(separator: "#").last ?? "") }
        reschedule(fireAtMillis: fireAt, existing: schedule, consumingOccurrenceMillis: consumedOccurrence) { [self] error in
            if let error {
                emitFailure(alarmId: alarmId, message: error.localizedDescription)
            } else {
                if schedule.keepNotificationAfterAlarmEnds != true {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(
                        withIdentifiers: [deliveredIdentifier ?? String(alarmId)]
                    )
                }
                emitEvent(WarmAlarmEventWire(
                    alarmId: alarmId,
                    type: .snoozed,
                    occurredAtMillis: nowMillis(),
                    snoozeDurationMillis: snoozeDurationMillis,
                    payload: schedule.payload
                ))
            }
            completion()
        }
    }

    private func actionSchedule(
        alarmId: Int64, content: UNNotificationContent?, occurrenceToken: String?, deliveredIdentifier: String?
    ) -> WarmAlarmScheduleData? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard let schedule = WarmAlarmStore.shared.load(id: alarmId) else { return nil }
        if let content {
            guard content.userInfo["occurrenceSeriesToken"] as? String == schedule.occurrenceSeriesToken else { return nil }
        }
        if let occurrenceToken {
            guard let deliveredAt = Int64(occurrenceToken.split(separator: "#").last ?? "") else { return nil }
            // A retained notification must not consume or replace a later snooze, including after relaunch.
            let isRecurringRequest = (schedule.recurrenceWeekdays ?? []).contains {
                deliveredIdentifier == "\(alarmId)#\($0)"
            }
            if let consumed = schedule.consumedOccurrenceMillis, deliveredAt <= consumed { return nil }
            if !isRecurringRequest, let snoozeUntil = schedule.activeSnoozeUntilMillis, deliveredAt < snoozeUntil { return nil }
            if activeAlarmId == alarmId, let activeOccurrenceToken,
               let activeDeliveredAt = Int64(activeOccurrenceToken.split(separator: "#").last ?? ""),
               deliveredAt < activeDeliveredAt { return nil }
        }
        return schedule
    }

    private func stopAudioIfPlaying(alarmId: Int64, occurrenceToken: String?) {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard activeAlarmId == alarmId,
              occurrenceToken == nil || activeOccurrenceToken == occurrenceToken else { return }
        stopAudio()
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
        content.userInfo["warmAlarmStopActionTitle"] = schedule.stopActionTitle ?? "Stop"
        content.userInfo["warmAlarmSnoozeActionTitle"] = schedule.snoozeActionTitle ?? "Snooze"
        content.categoryIdentifier = Self.notificationCategory(
            stopTitle: schedule.stopActionTitle, snoozeTitle: schedule.snoozeActionTitle
        ).identifier
        return content
    }

    // MARK: - Category registration

    static func ownsCategory(_ identifier: String) -> Bool {
        if identifier == categoryIdentifier { return true }
        let prefix = categoryIdentifier + ":"
        guard identifier.hasPrefix(prefix) else { return false }
        let digest = identifier.dropFirst(prefix.count)
        return digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func notificationCategory(stopTitle: String?, snoozeTitle: String?) -> UNNotificationCategory {
        let stopTitle = stopTitle ?? "Stop"
        let snoozeTitle = snoozeTitle ?? "Snooze"
        let identifier: String
        if stopTitle == "Stop", snoozeTitle == "Snooze" {
            identifier = categoryIdentifier
        } else {
            // Length-prefixing keeps distinct title pairs distinct, including Unicode and delimiter text.
            let input = "\(stopTitle.utf8.count):\(stopTitle)\(snoozeTitle)"
            let digest = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
            identifier = categoryIdentifier + ":" + digest
        }
        return UNNotificationCategory(
            identifier: identifier,
            actions: [
                UNNotificationAction(identifier: stopActionIdentifier, title: stopTitle, options: .destructive),
                UNNotificationAction(identifier: snoozeActionIdentifier, title: snoozeTitle, options: [])
            ],
            intentIdentifiers: [], options: []
        )
    }

    static func registerCategories(
        for contents: [UNNotificationContent] = [],
        read: @escaping (@escaping (Set<UNNotificationCategory>) -> Void) -> Void = { completion in
            UNUserNotificationCenter.current().getNotificationCategories(completionHandler: completion)
        },
        write: @escaping (Set<UNNotificationCategory>) -> Void = {
            UNUserNotificationCenter.current().setNotificationCategories($0)
        },
        completion: @escaping () -> Void = {}
    ) {
        var required: Set<UNNotificationCategory> = [notificationCategory(stopTitle: nil, snoozeTitle: nil)]
        for content in contents where ownsCategory(content.categoryIdentifier) {
            required.insert(notificationCategory(
                stopTitle: content.userInfo["warmAlarmStopActionTitle"] as? String,
                snoozeTitle: content.userInfo["warmAlarmSnoozeActionTitle"] as? String
            ))
        }
        let categories = required
        let identifiers = Set(categories.map(\.identifier))
        categoryMutationQueue.enqueue { finish in
            read { existing in
                let preserved = existing.filter { !identifiers.contains($0.identifier) }
                write(Set(preserved).union(categories))
                completion()
                finish()
            }
        }
    }

    // MARK: - Audio

    private func startAudio(alarmId: Int64, occurrenceToken: String, for schedule: WarmAlarmScheduleData?) -> Bool? {
        playbackLock.lock()
        defer { playbackLock.unlock() }
        guard let schedule,
              let storedSchedule = WarmAlarmStore.shared.load(id: alarmId),
              storedSchedule.occurrenceSeriesToken == schedule.occurrenceSeriesToken else { return nil }
        // An accepted delivery owns audio from here on, even when it falls back to the notification sound.
        stopAudio()
        let url: URL?
        switch WarmAlarmAudioSource.select(filePath: schedule.filePath, assetPath: schedule.assetPath) {
        case let .file(path):
            url = URL(fileURLWithPath: path)
        case let .asset(asset):
            url = WarmAlarmAudioSource.assetURL(for: asset)
        case .none:
            return false
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            emitPlaybackFailure(alarmId: alarmId, code: .audioFileNotFound, message: "Custom alarm audio was not found.")
            return false
        }
        do {
            let player = try audioPlayerFactory(url)
            let steps = schedule.fadeSteps
            if let first = steps?.first, first.timeMillis == 0 {
                player.volume = max(0.0, min(1.0, Float(first.volume)))
            } else if let volume = schedule.volume {
                player.volume = max(0.0, min(1.0, Float(volume)))
            } else {
                player.volume = 1.0
            }
            player.numberOfLoops = schedule.loop ? -1 : 0
            guard playAudio(player) else {
                player.stop()
                emitPlaybackFailure(alarmId: alarmId, code: .audioPlaybackFailed, message: "Custom alarm audio did not start.")
                return false
            }
            activePlayer = player
            activeAlarmId = alarmId
            activeOccurrenceToken = occurrenceToken
            if let steps { applyFadeSteps(steps, to: player) }
            if schedule.volumeEnforced == true { startVolumeEnforcer(for: player) }
            return true
        } catch {
            emitPlaybackFailure(alarmId: alarmId, code: .audioPlaybackFailed, message: error.localizedDescription)
            return false
        }
    }

    private func emitPlaybackFailure(alarmId: Int64, code: WarmAlarmFailureCodeWire, message: String) {
        emitEvent(WarmAlarmEventWire(
            alarmId: alarmId, type: .failed, occurredAtMillis: nowMillis(),
            failure: WarmAlarmFailureWire(code: code, message: message)
        ))
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
        activeOccurrenceToken = nil
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {}

    // MARK: - Reschedule (snooze)

    private func reschedule(
        fireAtMillis: Int64, existing: WarmAlarmScheduleData, consumingOccurrenceMillis: Int64?,
        completion: @escaping (Error?) -> Void
    ) {
        let updated = existing.withActiveSnooze(untilMillis: fireAtMillis, consumingOccurrenceMillis: consumingOccurrenceMillis)
        let content = makeContent(from: updated)
        let delay = max(1.0, Double(fireAtMillis - nowMillis()) / 1000.0)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: String(existing.id), content: content, trigger: trigger)
        pendingNotificationReader { [self] pending in
            let previous = pending.filter {
                $0.identifier == request.identifier
                    && Self.ownsCategory($0.content.categoryIdentifier)
                    && $0.content.userInfo["alarmId"] as? String == String(existing.id)
            }
            notificationAdder(request) { [self] error in
                guard let error else {
                    WarmAlarmStore.shared.save(updated)
                    completion(nil)
                    return
                }
                // The failed add never commits intent; restore any previous request sharing this identifier.
                WarmAlarmRecovery.recoverAll(previous, recover: notificationAdder) { restored in
                    if case let .failure(restoreError) = restored {
                        completion(PigeonError(
                            code: "scheduling-rollback-failed",
                            message: "Snooze failed: \(error.localizedDescription); restoring the previous request also failed: \(restoreError.localizedDescription)",
                            details: nil
                        ))
                    } else {
                        completion(error)
                    }
                }
            }
        }
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
