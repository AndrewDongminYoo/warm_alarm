import Flutter
import UIKit
import UserNotifications

enum WarmAlarmRequestRegistration {
    static func addAtomically<Request>(
        _ requests: [Request],
        identifier: @escaping (Request) -> String,
        add: @escaping (Request, @escaping (Error?) -> Void) -> Void,
        rollback: @escaping ([String]) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        let identifiers = requests.map(identifier)

        func addNext(at index: Int) {
            guard index < requests.count else {
                completion(nil)
                return
            }
            add(requests[index]) { error in
                if let error {
                    rollback(identifiers)
                    completion(error)
                    return
                }
                addNext(at: index + 1)
            }
        }

        addNext(at: 0)
    }
}

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
    private let delegate: WarmAlarmDelegate
    private static let killWarningNotifId = "warm_alarm_kill_warning_notif"
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(delegate: WarmAlarmDelegate) {
        self.delegate = delegate
        super.init()
        setupLifecycleObservers()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default
        // Scene-based apps (iOS 13+, UIApplicationSceneManifest declared): UIKit routes
        // foreground/background transitions through UISceneDelegate, not UIApplicationDelegate.
        lifecycleObservers.append(center.addObserver(
            forName: UIScene.willDeactivateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.postKillWarningIfNeeded() })
        lifecycleObservers.append(center.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelKillWarning() })
        // Legacy apps without UIApplicationSceneManifest.
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.postKillWarningIfNeeded() })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelKillWarning() })
        // Real termination (app running in foreground/background, not suspended):
        // warn for any scheduled-or-ringing alarm. The resign-active observers above
        // stay ringing-gated because they fire on every backgrounding; willTerminate
        // fires only on an actual quit, so broadening its guard is safe and spam-free.
        // iOS does not deliver willTerminate to a *suspended* app cleared from the app
        // switcher, so that case is inherently uncovered here.
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.postKillWarningOnTerminate() })
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let binaryMessenger = registrar.messenger()
        let eventsApi = WarmAlarmEventsApi(binaryMessenger: binaryMessenger)
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi)
        let instance = WarmAlarmPlugin(delegate: delegate)

        UNUserNotificationCenter.current().delegate = delegate
        WarmAlarmDelegate.registerCategories()
        WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
        registrar.publish(instance)
    }

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let stored = WarmAlarmStore.shared.loadAll()
        let recoverableAlarms = stored.values.filter { data in
            WarmAlarmRecurrence.shouldRecover(
                scheduledAtMillis: data.scheduledAtMillis,
                weekdays: data.recurrenceWeekdays,
                activeSnoozeUntilMillis: data.activeSnoozeUntilMillis,
                nowMillis: nowMillis)
        }
        guard !recoverableAlarms.isEmpty else {
            completion(.success(()))
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let pendingIds = Set(pending.map { $0.identifier })
            self.recoverAlarms(
                recoverableAlarms,
                startingAt: 0,
                pendingIdentifiers: pendingIds,
                nowMillis: nowMillis,
                center: center,
                completion: completion
            )
        }
    }

    private func recoverAlarms(
        _ alarms: [WarmAlarmScheduleData],
        startingAt index: Int,
        pendingIdentifiers: Set<String>,
        nowMillis: Int64,
        center: UNUserNotificationCenter,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard index < alarms.count else {
            completion(.success(()))
            return
        }

        let schedule = alarms[index]
        let content = delegate.makeContent(from: schedule)
        let missingIdentifiers = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: schedule.id,
            weekdays: schedule.recurrenceWeekdays,
            activeSnoozeUntilMillis: schedule.activeSnoozeUntilMillis,
            nowMillis: nowMillis,
            pendingIdentifiers: pendingIdentifiers
        )
        let requests = missingIdentifiers.map {
            Self.makeRecoveryRequest(identifier: $0, schedule: schedule, content: content, nowMillis: nowMillis)
        }
        guard !requests.isEmpty else {
            recoverAlarms(
                alarms,
                startingAt: index + 1,
                pendingIdentifiers: pendingIdentifiers,
                nowMillis: nowMillis,
                center: center,
                completion: completion
            )
            return
        }

        Self.addRequestsAtomically(requests, center: center) { error in
            if let error {
                completion(.failure(error))
                return
            }
            self.recoverAlarms(
                alarms,
                startingAt: index + 1,
                pendingIdentifiers: pendingIdentifiers,
                nowMillis: nowMillis,
                center: center,
                completion: completion
            )
        }
    }

    private static func makeRecoveryRequest(
        identifier: String,
        schedule: WarmAlarmScheduleData,
        content: UNNotificationContent,
        nowMillis: Int64
    ) -> UNNotificationRequest {
        let fireAtMillis = WarmAlarmRecurrence.recoveryFireAtMillis(
            identifier: identifier,
            scheduledAtMillis: schedule.scheduledAtMillis,
            activeSnoozeUntilMillis: schedule.activeSnoozeUntilMillis,
            nowMillis: nowMillis
        )
        let fireDate = Date(timeIntervalSince1970: Double(fireAtMillis) / 1000.0)
        if let separator = identifier.lastIndex(of: "#"),
           let isoWeekday = Int64(identifier[identifier.index(after: separator)...]) {
            let time = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
            var components = DateComponents()
            components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
            components.hour = time.hour
            components.minute = time.minute
            return UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private static func addRequestsAtomically(
        _ requests: [UNNotificationRequest],
        center: UNUserNotificationCenter,
        completion: @escaping (Error?) -> Void
    ) {
        WarmAlarmRequestRegistration.addAtomically(
            requests,
            identifier: { $0.identifier },
            add: { request, completion in
                center.add(request, withCompletionHandler: completion)
            },
            rollback: { identifiers in
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            },
            completion: completion
        )
    }

    func getCapabilities(completion: @escaping (Result<WarmAlarmCapabilitiesWire, Error>) -> Void) {
        completion(.success(WarmAlarmCapabilitiesWire(
            exactScheduling: .limited,
            notificationScheduling: .supported,
            backgroundAudioPlayback: .limited,
            fullScreenPresentation: .unsupported,
            wakeCheck: .unsupported,
            liveActivity: .supported
        )))
    }

    func getPermissionState(completion: @escaping (Result<WarmAlarmPermissionStateWire, Error>) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            completion(.success(WarmAlarmPermissionStateWire(
                notificationsGranted: granted,
                exactAlarmGranted: false,
                fullScreenIntentGranted: false
            )))
        }
    }

    func getReadiness(completion: @escaping (Result<WarmAlarmReadinessWire, Error>) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            var reasons: [WarmAlarmReadinessReasonWire] = [.backgroundExecutionLimited]
            if !granted { reasons.insert(.notificationPermissionDenied, at: 0) }
            let level: WarmAlarmReadinessLevelWire = granted ? .limited : .blocked
            completion(.success(WarmAlarmReadinessWire(level: level, reasons: reasons)))
        }
    }

    /// Builds the notification request(s) for a schedule.
    ///
    /// A non-recurring alarm produces a single one-shot request keyed by the alarm
    /// id. A recurring alarm produces one repeating `UNCalendarNotificationTrigger`
    /// per selected weekday, keyed by `"{id}#{isoWeekday}"`, so the series survives
    /// app termination without needing a re-arm on fire.
    private static func makeRequests(
        for schedule: WarmAlarmScheduleWire,
        content: UNNotificationContent
    ) -> [UNNotificationRequest] {
        let fireDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1000.0)
        if let weekdays = schedule.recurrence?.weekdays, !weekdays.isEmpty {
            let time = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
            return weekdays.map { iso in
                var components = DateComponents()
                components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: iso)
                components.hour = time.hour
                components.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                return UNNotificationRequest(
                    identifier: "\(schedule.id)#\(iso)", content: content, trigger: trigger)
            }
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return [UNNotificationRequest(identifier: String(schedule.id), content: content, trigger: trigger)]
    }

    func scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void
    ) {
        // Clear any prior requests for this id (one-shot "{id}" plus per-weekday
        // "{id}#{weekday}") so re-scheduling with a different weekday set does not
        // leave orphaned repeating triggers armed.
        let center = UNUserNotificationCenter.current()
        var staleIdentifiers = [String(schedule.id)]
        if let previousWeekdays = WarmAlarmStore.shared.load(id: schedule.id)?.recurrenceWeekdays {
            staleIdentifiers += previousWeekdays.map { "\(schedule.id)#\($0)" }
        }
        center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

        WarmAlarmStore.shared.save(.from(wire: schedule))

        let content = delegate.makeContent(from: .from(wire: schedule))
        let requests = Self.makeRequests(for: schedule, content: content)
        Self.addRequestsAtomically(requests, center: center) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                WarmAlarmStore.shared.remove(id: schedule.id)
                self.delegate.emitFailure(alarmId: schedule.id, message: error.localizedDescription)
                completion(.success(WarmAlarmScheduleResultWire(
                    alarmId: schedule.id,
                    readiness: WarmAlarmReadinessWire(level: .limited, reasons: [.backgroundExecutionLimited]),
                    warning: WarmAlarmWarningWire(message: "Scheduling failed: \(error.localizedDescription)")
                )))
                return
            }
            self.delegate.emitScheduled(alarmId: schedule.id)
            self.getReadiness { result in
                let readiness = (try? result.get())
                    ?? WarmAlarmReadinessWire(level: .limited, reasons: [.backgroundExecutionLimited])
                completion(.success(WarmAlarmScheduleResultWire(
                    alarmId: schedule.id, readiness: readiness, warning: nil)))
            }
        }
    }

    func cancelAlarm(id: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        delegate.stopIfPlaying(alarmId: id)
        // Cancelling tears down the whole series: the one-shot id plus every
        // per-weekday repeating request ("{id}#{isoWeekday}").
        var identifiers = [String(id)]
        if let weekdays = WarmAlarmStore.shared.load(id: id)?.recurrenceWeekdays {
            identifiers += weekdays.map { "\(id)#\($0)" }
        }
        WarmAlarmStore.shared.remove(id: id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        completion(.success(()))
    }

    func cancelAllAlarms(completion: @escaping (Result<Void, Error>) -> Void) {
        delegate.stopAllIfPlaying()
        WarmAlarmStore.shared.clear()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        completion(.success(()))
    }

    func getScheduledAlarms(completion: @escaping (Result<[WarmAlarmSnapshotWire], Error>) -> Void) {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let snapshots = WarmAlarmStore.shared.loadAll().map { _, data in
            WarmAlarmSnapshotWire(
                id: data.id,
                scheduledAtMillis: data.snapshotScheduledAtMillis(nowMillis: nowMillis),
                notification: WarmAlarmNotificationWire(
                    title: data.notificationTitle,
                    body: data.notificationBody,
                    stopActionTitle: data.stopActionTitle,
                    snoozeActionTitle: data.snoozeActionTitle,
                    keepNotificationAfterAlarmEnds: data.keepNotificationAfterAlarmEnds ?? false
                ),
                audio: WarmAlarmAudioWire(
                    filePath: data.filePath,
                    assetPath: data.assetPath,
                    loop: data.loop,
                    volume: data.volume,
                    fadeInDurationMillis: data.fadeInDurationMillis,
                    vibrate: data.vibrate,
                    volumeEnforced: data.volumeEnforced ?? false,
                    fadeSteps: data.fadeSteps?.map {
                        WarmAlarmVolumeFadeStepWire(timeMillis: $0.timeMillis, volume: $0.volume)
                    }
                ),
                recurrence: data.recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) },
                snooze: data.snoozeDurationMillis.map { WarmAlarmSnoozeWire(durationMillis: $0) },
                payload: data.payload
            )
        }
        completion(.success(snapshots))
    }

    func setKillWarning(
        title: String, body: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        UserDefaults.standard.setValue(["title": title, "body": body], forKey: "warm_alarm_kill_warning")
        completion(.success(()))
    }

    func clearKillWarning(completion: @escaping (Result<Void, Error>) -> Void) {
        UserDefaults.standard.removeObject(forKey: "warm_alarm_kill_warning")
        completion(.success(()))
    }

    func isRinging(alarmId: Int64?, completion: @escaping (Result<Bool, Error>) -> Void) {
        let playingId = delegate.currentlyPlayingAlarmId
        if let id = alarmId {
            completion(.success(playingId == id))
        } else {
            completion(.success(playingId != nil))
        }
    }

    private func postKillWarningIfNeeded() {
        guard delegate.currentlyPlayingAlarmId != nil,
              let dict = UserDefaults.standard.dictionary(forKey: "warm_alarm_kill_warning"),
              let title = dict["title"] as? String,
              let body = dict["body"] as? String
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: WarmAlarmPlugin.killWarningNotifId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func cancelKillWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [WarmAlarmPlugin.killWarningNotifId])
    }

    /// Posts the kill warning on genuine termination (`willTerminate`), for any
    /// alarm that is scheduled in the future or currently ringing. Shares the
    /// notification id with `postKillWarningIfNeeded()` so the two paths coalesce
    /// into one notification when both fire during a ring-then-terminate.
    private func postKillWarningOnTerminate() {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let hasFutureAlarm = WarmAlarmStore.shared.loadAll().values.contains { data in
            data.snapshotScheduledAtMillis(nowMillis: nowMillis) > nowMillis
        }
        guard hasFutureAlarm || delegate.currentlyPlayingAlarmId != nil,
              let dict = UserDefaults.standard.dictionary(forKey: "warm_alarm_kill_warning"),
              let title = dict["title"] as? String,
              let body = dict["body"] as? String
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Deliver immediately and block briefly so the request is enqueued before the
        // process dies (willTerminate grants ~5s). The add completion runs off the main
        // queue, so waiting here does not deadlock.
        let request = UNNotificationRequest(
            identifier: WarmAlarmPlugin.killWarningNotifId, content: content, trigger: nil)
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
}
