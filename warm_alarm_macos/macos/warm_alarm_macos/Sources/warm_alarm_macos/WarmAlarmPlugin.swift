import AppKit
import FlutterMacOS
import UserNotifications

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
    private let delegate: WarmAlarmDelegate
    private static let killWarningNotifId = "warm_alarm_kill_warning_notif"

    init(delegate: WarmAlarmDelegate) {
        self.delegate = delegate
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let binaryMessenger = registrar.messenger
        let eventsApi = WarmAlarmEventsApi(binaryMessenger: binaryMessenger)
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi)
        let instance = WarmAlarmPlugin(delegate: delegate)

        UNUserNotificationCenter.current().delegate = delegate
        WarmAlarmDelegate.registerCategories()
        WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
        instance.setupLifecycleObservers()
        registrar.publish(instance)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: NSApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        // Real termination (Cmd-Q / system quit): warn for any scheduled-or-ringing
        // alarm. The resign-active observer above stays ringing-gated because it fires
        // on every focus loss; willTerminate fires only on an actual quit, so
        // broadening its guard is safe and spam-free.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
    }

    @objc private func appWillResignActive() {
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

    @objc private func appDidBecomeActive() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [WarmAlarmPlugin.killWarningNotifId])
    }

    /// Posts the kill warning on genuine termination (`willTerminate`), for any
    /// alarm scheduled in the future or currently ringing. Shares the notification
    /// id with `appWillResignActive` so the two paths coalesce into one notification.
    @objc private func appWillTerminate() {
        let now = Date()
        let hasFutureAlarm = WarmAlarmStore.shared.loadAll().values.contains { data in
            Date(timeIntervalSince1970: Double(data.scheduledAtMillis) / 1000.0) > now
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
        // process exits. The add completion runs off the main queue, so no deadlock.
        let request = UNNotificationRequest(
            identifier: WarmAlarmPlugin.killWarningNotifId, content: content, trigger: nil)
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        let now = Date()
        let stored = WarmAlarmStore.shared.loadAll()
        let futureAlarms = stored.values.filter { data in
            Date(timeIntervalSince1970: Double(data.scheduledAtMillis) / 1000.0) > now
        }
        guard !futureAlarms.isEmpty else {
            completion(.success(()))
            return
        }
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let pendingIds = Set(pending.map { $0.identifier })
            for data in futureAlarms {
                let idStr = String(data.id)
                guard !pendingIds.contains(idStr) else { continue }
                let content = self.delegate.makeContent(from: data)
                let fireDate = Date(timeIntervalSince1970: Double(data.scheduledAtMillis) / 1000.0)
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: idStr, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { _ in }
            }
            completion(.success(()))
        }
    }

    func getCapabilities(completion: @escaping (Result<WarmAlarmCapabilitiesWire, Error>) -> Void) {
        completion(.success(WarmAlarmCapabilitiesWire(
            exactScheduling: .unsupported,
            notificationScheduling: .supported,
            backgroundAudioPlayback: .limited,
            fullScreenPresentation: .unsupported,
            wakeCheck: .unsupported,
            liveActivity: .unsupported
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
        // For a recurring alarm we register one repeating trigger per weekday.
        // Add the extra weekday requests fire-and-forget; the first request drives
        // the readiness/error callback below.
        for extra in requests.dropFirst() {
            center.add(extra) { _ in }
        }

        center.add(requests[0]) { [weak self] error in
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
        WarmAlarmStore.shared.clear()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        completion(.success(()))
    }

    func getScheduledAlarms(completion: @escaping (Result<[WarmAlarmSnapshotWire], Error>) -> Void) {
        let snapshots = WarmAlarmStore.shared.loadAll().map { _, data in
            WarmAlarmSnapshotWire(
                id: data.id,
                scheduledAtMillis: data.scheduledAtMillis,
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
}
