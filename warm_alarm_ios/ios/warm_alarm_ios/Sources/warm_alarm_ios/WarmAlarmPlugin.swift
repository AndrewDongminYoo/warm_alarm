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

final class WarmAlarmMutationQueue {
    typealias Mutation = (@escaping () -> Void) -> Void

    private let queue: DispatchQueue
    private var mutations = [Mutation]()
    private var isRunning = false

    init(label: String) {
        queue = DispatchQueue(label: label)
    }

    func enqueue(_ mutation: @escaping Mutation) {
        queue.async(execute: { [weak self] in
            guard let self else { return }
            self.mutations.append(mutation)
            self.startNextMutation()
        })
    }

    private func startNextMutation() {
        guard !isRunning, !mutations.isEmpty else { return }
        isRunning = true
        let mutation = mutations.removeFirst()
        mutation { [weak self] in
            self?.queue.async(execute: { [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.startNextMutation()
            })
        }
    }
}

// Pigeon provides non-Sendable callbacks.
// This immutable envelope invokes each callback once on the main platform thread.
// Remove @unchecked Sendable when Pigeon provides Sendable callbacks.
final class WarmAlarmPlatformReply: @unchecked Sendable {
    private let reply: () -> Void

    private init(reply: @escaping () -> Void) {
        self.reply = reply
    }

    static func performOnMain(_ action: @escaping () -> Void) {
        let reply = WarmAlarmPlatformReply(reply: action)
        DispatchQueue.main.async {
            reply.reply()
        }
    }

    /// Opens `url` and reports whether the system accepted it.
    /// Both outcomes are wrapped up front because the completion handler cannot carry
    /// non-Sendable Pigeon callbacks across the concurrency boundary.
    static func open(_ url: URL, then handler: @escaping (Bool) -> Void) {
        let onOpened = WarmAlarmPlatformReply { handler(true) }
        let onRejected = WarmAlarmPlatformReply { handler(false) }
        performOnMain {
            UIApplication.shared.open(url, options: [:]) { opened in
                (opened ? onOpened : onRejected).reply()
            }
        }
    }

    static func complete<Value>(
        _ result: Result<Value, Error>,
        completion: @escaping (Result<Value, Error>) -> Void,
        finish: @escaping () -> Void
    ) {
        let reply = WarmAlarmPlatformReply {
            completion(result)
            finish()
        }
        performOnMain {
            reply.reply()
        }
    }
}

enum WarmAlarmRecovery {
    static func recoverAll<Alarm>(
        _ alarms: [Alarm],
        recover: @escaping (Alarm, @escaping (Error?) -> Void) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func recoverNext(at index: Int, firstError: Error?) {
            guard index < alarms.count else {
                if let firstError {
                    completion(.failure(firstError))
                } else {
                    completion(.success(()))
                }
                return
            }
            recover(alarms[index]) { error in
                recoverNext(at: index + 1, firstError: firstError ?? error)
            }
        }

        recoverNext(at: 0, firstError: nil)
    }
}

struct WarmAlarmRequestSelection {
    let requests: [UNNotificationRequest]
    let omittedFallbackCount: Int
}

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
    private let delegate: WarmAlarmDelegate
    private let notificationMutationQueue: WarmAlarmMutationQueue
    private static let killWarningNotifId = "warm_alarm_kill_warning_notif"
    private static let killWarningDefaultsKey = "warm_alarm_kill_warning"
    private static let fallbackCount = 6
    private static let fallbackIntervalMillis: Int64 = 30_000
    private static let pendingNotificationLimit = 64
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(
        delegate: WarmAlarmDelegate,
        notificationMutationQueue: WarmAlarmMutationQueue
    ) {
        self.delegate = delegate
        self.notificationMutationQueue = notificationMutationQueue
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
        // ponytail: serializes all Apple notification mutations; split by alarm ID only if contention is measured.
        let notificationMutationQueue = WarmAlarmMutationQueue(label: "warm_alarm.notification_mutation")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: notificationMutationQueue
        )
        let instance = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: notificationMutationQueue
        )

        UNUserNotificationCenter.current().delegate = delegate
        WarmAlarmDelegate.registerCategories()
        WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
        registrar.publish(instance)
    }

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
            let stored = WarmAlarmStore.shared.loadAll()
            let recoverableAlarms = stored.values
                .filter { Self.shouldRecover(schedule: $0, nowMillis: nowMillis) }
                .sorted {
                    let leftAnchor = $0.fallbackAnchorMillis ?? $0.scheduledAtMillis
                    let rightAnchor = $1.fallbackAnchorMillis ?? $1.scheduledAtMillis
                    return leftAnchor == rightAnchor ? $0.id < $1.id : leftAnchor < rightAnchor
                }
            guard !recoverableAlarms.isEmpty else {
                WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                return
            }
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { [weak self] pending in
                guard let self else {
                    finish()
                    return
                }
                self.recoverAlarms(
                    recoverableAlarms,
                    pendingIdentifiers: Set(pending.map { $0.identifier }),
                    nowMillis: nowMillis,
                    center: center
                ) { result in
                    WarmAlarmPlatformReply.complete(result, completion: completion, finish: finish)
                }
            }
        }
    }

    private func recoverAlarms(
        _ alarms: [WarmAlarmScheduleData],
        pendingIdentifiers: Set<String>,
        nowMillis: Int64,
        center: UNUserNotificationCenter,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestGroups = alarms.map { schedule in
            let content = delegate.makeContent(from: schedule)
            return Self.makeRecoveryRequests(
                for: schedule,
                nowMillis: nowMillis,
                pendingIdentifiers: pendingIdentifiers,
                content: content
            )
        }
        let reservedSlotCount = Self.killWarningReservedSlotCount(
            isConfigured: Self.isKillWarningConfigured,
            pendingIdentifiers: pendingIdentifiers
        )
        guard let selection = Self.selectRecoveryRequestsWithinPendingLimit(
            requestGroups,
            pendingIdentifiers: pendingIdentifiers,
            reservedSlotCount: reservedSlotCount,
            limit: Self.pendingNotificationLimit
        ) else {
            let coreCount = Self.coreRequestCount(in: requestGroups.flatMap { $0 })
            completion(.failure(Self.pendingLimitError(
                requiredCoreCount: coreCount,
                availableCount: Self.availableRequestSlotCount(
                    pendingIdentifiers: pendingIdentifiers,
                    replacingIdentifiers: [],
                    reservedSlotCount: reservedSlotCount,
                    limit: Self.pendingNotificationLimit
                )
            )))
            return
        }
        let selectedIdentifiers = Set(selection.requests.map(\.identifier))
        WarmAlarmRecovery.recoverAll(
            requestGroups,
            recover: { requests, completion in
                let selectedRequests = requests.filter { selectedIdentifiers.contains($0.identifier) }
                guard !selectedRequests.isEmpty else {
                    completion(nil)
                    return
                }
                Self.addRequestsAtomically(
                    selectedRequests,
                    center: center,
                    completion: completion
                )
            },
            completion: completion
        )
    }

    static func shouldRecover(
        schedule: WarmAlarmScheduleData,
        nowMillis: Int64
    ) -> Bool {
        if WarmAlarmRecurrence.shouldRecover(
            scheduledAtMillis: schedule.scheduledAtMillis,
            weekdays: schedule.recurrenceWeekdays,
            activeSnoozeUntilMillis: schedule.activeSnoozeUntilMillis,
            nowMillis: nowMillis
        ) {
            return true
        }
        guard let anchor = schedule.fallbackAnchorMillis else { return false }
        return fallbackFireAtMillis(anchorMillis: anchor, index: fallbackCount) > nowMillis
    }

    static func makeRecoveryRequests(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        pendingIdentifiers: Set<String>,
        content: UNNotificationContent,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        var expectedIdentifiers: [String]
        if let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty {
            expectedIdentifiers = weekdays.map { "\(schedule.id)#\($0)" }
            if let activeSnoozeUntilMillis = schedule.activeSnoozeUntilMillis,
               activeSnoozeUntilMillis > nowMillis {
                expectedIdentifiers.append(String(schedule.id))
            }
        } else if schedule.activeSnoozeUntilMillis.map({ $0 > nowMillis }) == true
            || schedule.scheduledAtMillis > nowMillis {
            expectedIdentifiers = [String(schedule.id)]
        } else {
            expectedIdentifiers = []
        }

        if let anchor = schedule.fallbackAnchorMillis {
            expectedIdentifiers += fallbackIdentifiers(for: schedule.id).enumerated().compactMap { index, identifier in
                fallbackFireAtMillis(anchorMillis: anchor, index: index + 1) > nowMillis ? identifier : nil
            }
        }

        return deduplicatedRequests(
            expectedIdentifiers
                .filter { !pendingIdentifiers.contains($0) }
                .map {
                    makeRecoveryRequest(
                        identifier: $0,
                        schedule: schedule,
                        content: content,
                        nowMillis: nowMillis,
                        calendar: calendar
                    )
                }
        )
    }

    private static func makeRecoveryRequest(
        identifier: String,
        schedule: WarmAlarmScheduleData,
        content: UNNotificationContent,
        nowMillis: Int64,
        calendar: Calendar
    ) -> UNNotificationRequest {
        if let fallbackIndex = fallbackIndex(for: identifier, alarmId: schedule.id),
           let anchor = schedule.fallbackAnchorMillis {
            let fireAtMillis = fallbackFireAtMillis(anchorMillis: anchor, index: fallbackIndex)
            let fireDate = Date(timeIntervalSince1970: Double(fireAtMillis) / 1000.0)
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            return UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        }
        let fireAtMillis = WarmAlarmRecurrence.recoveryFireAtMillis(
            identifier: identifier,
            scheduledAtMillis: schedule.scheduledAtMillis,
            activeSnoozeUntilMillis: schedule.activeSnoozeUntilMillis,
            nowMillis: nowMillis
        )
        let fireDate = Date(timeIntervalSince1970: Double(fireAtMillis) / 1000.0)
        if let separator = identifier.lastIndex(of: "#"),
           let isoWeekday = Int64(identifier[identifier.index(after: separator)...]) {
            let time = calendar.dateComponents([.hour, .minute], from: fireDate)
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
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    static func addRequestsAtomically(
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
            liveActivity: .unsupported
        )))
    }

    func getPermissionState(completion: @escaping (Result<WarmAlarmPermissionStateWire, Error>) -> Void) {
        captureNotificationSnapshot { permissionState, _ in
            completion(.success(permissionState))
        }
    }

    func getReadiness(completion: @escaping (Result<WarmAlarmReadinessWire, Error>) -> Void) {
        captureNotificationSnapshot { _, readiness in
            completion(.success(readiness))
        }
    }

    func requestNotificationPermission(
        completion: @escaping (Result<WarmAlarmRemediationResultWire, Error>) -> Void
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: {})
                return
            }
            self.completeRemediation(status: .completed, completion: completion)
        }
    }

    func openReadinessSettings(
        reason: WarmAlarmReadinessReasonWire,
        completion: @escaping (Result<WarmAlarmRemediationResultWire, Error>) -> Void
    ) {
        guard reason == .notificationPermissionDenied else {
            completeRemediation(status: .unsupported, completion: completion)
            return
        }

        let settingsURLString: String
        if #available(iOS 16.0, *) {
            settingsURLString = UIApplication.openNotificationSettingsURLString
        } else {
            settingsURLString = UIApplication.openSettingsURLString
        }
        guard let settingsURL = URL(string: settingsURLString) else {
            completeRemediation(status: .unavailable, completion: completion)
            return
        }

        // The contract says a settings handoff reports the state before the user acted on it, so
        // the snapshot is taken while control is still in the app. Only the status is post-action.
        captureNotificationSnapshot { permissionState, readiness in
            WarmAlarmPlatformReply.open(settingsURL) { opened in
                self.replyRemediation(
                    status: opened ? .completed : .unavailable,
                    permissionState: permissionState,
                    readiness: readiness,
                    completion: completion
                )
            }
        }
    }

    /// Reads permission and readiness from one settings query so the two cannot disagree.
    private func captureNotificationSnapshot(
        _ handler: @escaping (WarmAlarmPermissionStateWire, WarmAlarmReadinessWire) -> Void
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            var reasons: [WarmAlarmReadinessReasonWire] = [.backgroundExecutionLimited]
            if !granted { reasons.insert(.notificationPermissionDenied, at: 0) }
            handler(
                WarmAlarmPermissionStateWire(
                    notificationsGranted: granted,
                    exactAlarmGranted: false,
                    fullScreenIntentGranted: false
                ),
                WarmAlarmReadinessWire(level: granted ? .limited : .blocked, reasons: reasons)
            )
        }
    }

    private func completeRemediation(
        status: WarmAlarmRemediationStatusWire,
        completion: @escaping (Result<WarmAlarmRemediationResultWire, Error>) -> Void
    ) {
        captureNotificationSnapshot { permissionState, readiness in
            self.replyRemediation(
                status: status,
                permissionState: permissionState,
                readiness: readiness,
                completion: completion
            )
        }
    }

    /// The notification-centre callbacks land on an arbitrary queue, so every reply goes back
    /// through the envelope that delivers it on the main platform thread.
    private func replyRemediation(
        status: WarmAlarmRemediationStatusWire,
        permissionState: WarmAlarmPermissionStateWire,
        readiness: WarmAlarmReadinessWire,
        completion: @escaping (Result<WarmAlarmRemediationResultWire, Error>) -> Void
    ) {
        WarmAlarmPlatformReply.complete(
            .success(WarmAlarmRemediationResultWire(
                status: status,
                permissionState: permissionState,
                readiness: readiness
            )),
            completion: completion,
            finish: {}
        )
    }

    /// Builds the notification request(s) for a schedule.
    ///
    /// A non-recurring alarm produces one primary request.
    /// A recurring alarm produces one repeating `UNCalendarNotificationTrigger`
    /// per selected weekday, keyed by `"{id}#{isoWeekday}"`.
    /// Every schedule also produces six one-shot fallback requests.
    /// Each fallback fires 30 seconds after the previous request.
    static func makeRequests(
        for schedule: WarmAlarmScheduleWire,
        content: UNNotificationContent,
        fallbackAnchorMillis: Int64,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        let fireDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1000.0)
        if let weekdays = schedule.recurrence?.weekdays, !weekdays.isEmpty {
            let time = calendar.dateComponents([.hour, .minute], from: fireDate)
            let recurringRequests = weekdays.map { iso in
                var components = DateComponents()
                components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: iso)
                components.hour = time.hour
                components.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                return UNNotificationRequest(
                    identifier: "\(schedule.id)#\(iso)", content: content, trigger: trigger)
            }
            return recurringRequests + makeFallbackRequests(
                alarmId: schedule.id,
                content: content,
                anchorMillis: fallbackAnchorMillis,
                calendar: calendar
            )
        }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let primaryRequest = UNNotificationRequest(
            identifier: String(schedule.id), content: content, trigger: trigger)
        return [primaryRequest] + makeFallbackRequests(
            alarmId: schedule.id,
            content: content,
            anchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )
    }

    static func makeSnoozeRequests(
        for schedule: WarmAlarmScheduleData,
        fireAtMillis: Int64,
        nowMillis: Int64,
        content: UNNotificationContent,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        let delay = max(1.0, Double(fireAtMillis - nowMillis) / 1000.0)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let primaryRequest = UNNotificationRequest(
            identifier: String(schedule.id), content: content, trigger: trigger)
        return [primaryRequest] + makeFallbackRequests(
            alarmId: schedule.id,
            content: content,
            anchorMillis: fireAtMillis,
            calendar: calendar
        )
    }

    static func fallbackAnchorMillis(
        for schedule: WarmAlarmScheduleWire,
        nowMillis: Int64,
        calendar: Calendar = .current
    ) -> Int64 {
        guard let weekdays = schedule.recurrence?.weekdays, !weekdays.isEmpty else {
            return schedule.scheduledAtMillis
        }
        let scheduledDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1000.0)
        let scheduledMinuteComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduledDate
        )
        guard let scheduledMinute = calendar.date(from: scheduledMinuteComponents) else {
            return schedule.scheduledAtMillis
        }
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000.0)
        let searchAfter = now < scheduledMinute ? scheduledMinute.addingTimeInterval(-0.001) : now
        return WarmAlarmRecurrence.nextOccurrenceMillis(
            scheduledAtMillis: schedule.scheduledAtMillis,
            weekdays: weekdays,
            afterMillis: Int64(searchAfter.timeIntervalSince1970 * 1000.0),
            calendar: calendar
        ) ?? schedule.scheduledAtMillis
    }

    static func fallbackIdentifiers(for alarmId: Int64) -> [String] {
        (1...fallbackCount).map { "\(alarmId)#fallback#\($0)" }
    }

    static func requestIdentifiers(for alarmId: Int64, recurrenceWeekdays: [Int64]?) -> [String] {
        [String(alarmId)]
            + (recurrenceWeekdays ?? []).map { "\(alarmId)#\($0)" }
            + fallbackIdentifiers(for: alarmId)
    }

    static func selectRequestsWithinPendingLimit(
        _ requests: [UNNotificationRequest],
        pendingIdentifiers: Set<String>,
        replacingIdentifiers: Set<String>,
        reservedSlotCount: Int = 0,
        limit: Int
    ) -> WarmAlarmRequestSelection? {
        let availableCount = availableRequestSlotCount(
            pendingIdentifiers: pendingIdentifiers,
            replacingIdentifiers: replacingIdentifiers,
            reservedSlotCount: reservedSlotCount,
            limit: limit
        )
        let uniqueRequests = deduplicatedRequests(requests)
        let coreRequests = uniqueRequests.filter { !isFallbackIdentifier($0.identifier) }
        guard coreRequests.count <= availableCount else { return nil }
        let fallbackRequests = uniqueRequests.filter { isFallbackIdentifier($0.identifier) }
        let selectedFallbacks = fallbackRequests.prefix(availableCount - coreRequests.count)
        return WarmAlarmRequestSelection(
            requests: coreRequests + Array(selectedFallbacks),
            omittedFallbackCount: fallbackRequests.count - selectedFallbacks.count
        )
    }

    static func selectRecoveryRequestsWithinPendingLimit(
        _ requestGroups: [[UNNotificationRequest]],
        pendingIdentifiers: Set<String>,
        reservedSlotCount: Int = 0,
        limit: Int
    ) -> WarmAlarmRequestSelection? {
        selectRequestsWithinPendingLimit(
            requestGroups.flatMap { $0 },
            pendingIdentifiers: pendingIdentifiers,
            replacingIdentifiers: [],
            reservedSlotCount: reservedSlotCount,
            limit: limit
        )
    }

    static func selectSnoozeRequestsWithinPendingLimit(
        _ requests: [UNNotificationRequest],
        pendingIdentifiers: Set<String>,
        isKillWarningConfigured: Bool,
        limit: Int
    ) -> WarmAlarmRequestSelection? {
        let reservedSlotCount = killWarningReservedSlotCount(
            isConfigured: isKillWarningConfigured,
            pendingIdentifiers: pendingIdentifiers
        )
        return selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pendingIdentifiers,
            replacingIdentifiers: Set(requests.map(\.identifier)),
            reservedSlotCount: reservedSlotCount,
            limit: limit
        )
    }

    static func selectSnoozeRequestsWithinPendingLimit(
        _ requests: [UNNotificationRequest],
        pendingIdentifiers: Set<String>
    ) -> WarmAlarmRequestSelection? {
        selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pendingIdentifiers,
            isKillWarningConfigured: isKillWarningConfigured,
            limit: pendingNotificationLimit
        )
    }

    static func killWarningReservedSlotCount(
        isConfigured: Bool,
        pendingIdentifiers: Set<String>
    ) -> Int {
        isConfigured && !pendingIdentifiers.contains(killWarningNotifId) ? 1 : 0
    }

    static func canConfigureKillWarning(
        pendingIdentifiers: Set<String>,
        limit: Int
    ) -> Bool {
        pendingIdentifiers.contains(killWarningNotifId) || pendingIdentifiers.count < limit
    }

    private static var isKillWarningConfigured: Bool {
        UserDefaults.standard.dictionary(forKey: killWarningDefaultsKey) != nil
    }

    private static func deduplicatedRequests(
        _ requests: [UNNotificationRequest]
    ) -> [UNNotificationRequest] {
        var seenIdentifiers = Set<String>()
        return requests.filter { seenIdentifiers.insert($0.identifier).inserted }
    }

    private static func coreRequestCount(in requests: [UNNotificationRequest]) -> Int {
        deduplicatedRequests(requests)
            .filter { !isFallbackIdentifier($0.identifier) }
            .count
    }

    private static func availableRequestSlotCount(
        pendingIdentifiers: Set<String>,
        replacingIdentifiers: Set<String>,
        reservedSlotCount: Int = 0,
        limit: Int
    ) -> Int {
        max(0, limit - pendingIdentifiers.subtracting(replacingIdentifiers).count - reservedSlotCount)
    }

    private static func isFallbackIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: "#")
        guard parts.count == 3,
              parts[1] == "fallback",
              let index = Int(parts[2]) else { return false }
        return (1...fallbackCount).contains(index)
    }

    static func isFallbackIdentifier(_ identifier: String, for alarmId: Int64) -> Bool {
        fallbackIndex(for: identifier, alarmId: alarmId) != nil
    }

    private static func fallbackIndex(for identifier: String, alarmId: Int64) -> Int? {
        let prefix = "\(alarmId)#fallback#"
        guard identifier.hasPrefix(prefix),
              let index = Int(identifier.dropFirst(prefix.count)),
              (1...fallbackCount).contains(index) else { return nil }
        return index
    }

    private static func fallbackFireAtMillis(anchorMillis: Int64, index: Int) -> Int64 {
        anchorMillis + Int64(index) * fallbackIntervalMillis
    }

    private static func makeFallbackRequests(
        alarmId: Int64,
        content: UNNotificationContent,
        anchorMillis: Int64,
        calendar: Calendar
    ) -> [UNNotificationRequest] {
        fallbackIdentifiers(for: alarmId).enumerated().map { index, identifier in
            let scheduledAtMillis = fallbackFireAtMillis(anchorMillis: anchorMillis, index: index + 1)
            let requestDate = Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1000.0)
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: requestDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }
    }

    private static func pendingLimitError(requiredCoreCount: Int, availableCount: Int) -> Error {
        let message = "The alarm needs \(requiredCoreCount) notification slots, "
            + "but iOS has \(availableCount) available."
        return PigeonError(
            code: "pending-notification-limit",
            message: message,
            details: nil
        )
    }

    static func fallbackCapacityWarning(omittedCount: Int) -> WarmAlarmWarningWire? {
        guard omittedCount > 0 else { return nil }
        let scheduledCount = fallbackCount - omittedCount
        let message = "iOS scheduled \(scheduledCount) of \(fallbackCount) fallback notifications "
            + "because the app reached the 64-notification limit."
        return WarmAlarmWarningWire(message: message)
    }

    func scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void
    ) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
            let fallbackAnchorMillis = Self.fallbackAnchorMillis(
                for: schedule,
                nowMillis: nowMillis
            )
            let storedSchedule = WarmAlarmScheduleData.from(
                wire: schedule,
                fallbackAnchorMillis: fallbackAnchorMillis
            )
            let content = self.delegate.makeContent(from: storedSchedule)
            let requests = Self.makeRequests(
                for: schedule,
                content: content,
                fallbackAnchorMillis: fallbackAnchorMillis
            )
            let center = UNUserNotificationCenter.current()
            let staleIdentifiers = Self.requestIdentifiers(
                for: schedule.id,
                recurrenceWeekdays: WarmAlarmStore.shared.load(id: schedule.id)?.recurrenceWeekdays
            )
            let replacingIdentifiers = Set(staleIdentifiers)
            center.getPendingNotificationRequests { [weak self] pendingRequests in
                guard let self else {
                    finish()
                    return
                }
                let pendingIdentifiers = Set(pendingRequests.map(\.identifier))
                let reservedSlotCount = Self.killWarningReservedSlotCount(
                    isConfigured: Self.isKillWarningConfigured,
                    pendingIdentifiers: pendingIdentifiers
                )
                guard let selection = Self.selectRequestsWithinPendingLimit(
                    requests,
                    pendingIdentifiers: pendingIdentifiers,
                    replacingIdentifiers: replacingIdentifiers,
                    reservedSlotCount: reservedSlotCount,
                    limit: Self.pendingNotificationLimit
                ) else {
                    let error = Self.pendingLimitError(
                        requiredCoreCount: Self.coreRequestCount(in: requests),
                        availableCount: Self.availableRequestSlotCount(
                            pendingIdentifiers: pendingIdentifiers,
                            replacingIdentifiers: replacingIdentifiers,
                            reservedSlotCount: reservedSlotCount,
                            limit: Self.pendingNotificationLimit
                        )
                    )
                    self.delegate.emitFailure(alarmId: schedule.id, message: error.localizedDescription)
                    WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                    return
                }

                self.delegate.clearHandledForegroundOccurrence(alarmId: schedule.id)
                center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
                WarmAlarmStore.shared.save(storedSchedule)
                let capacityWarning = Self.fallbackCapacityWarning(
                    omittedCount: selection.omittedFallbackCount
                )
                Self.addRequestsAtomically(
                    selection.requests,
                    center: center
                ) { [weak self] error in
                    guard let self else {
                        finish()
                        return
                    }
                    if let error {
                        WarmAlarmStore.shared.remove(id: schedule.id)
                        self.delegate.emitFailure(alarmId: schedule.id, message: error.localizedDescription)
                        WarmAlarmPlatformReply.complete(.success(WarmAlarmScheduleResultWire(
                            alarmId: schedule.id,
                            readiness: WarmAlarmReadinessWire(
                                level: .limited,
                                reasons: [.backgroundExecutionLimited]
                            ),
                            warning: WarmAlarmWarningWire(
                                message: "Scheduling failed: \(error.localizedDescription)"
                            )
                        )), completion: completion, finish: finish)
                        return
                    }
                    self.delegate.emitScheduled(alarmId: schedule.id)
                    self.getReadiness { result in
                        let readiness = (try? result.get())
                            ?? WarmAlarmReadinessWire(level: .limited, reasons: [.backgroundExecutionLimited])
                        WarmAlarmPlatformReply.complete(.success(WarmAlarmScheduleResultWire(
                            alarmId: schedule.id,
                            readiness: readiness,
                            warning: capacityWarning
                        )), completion: completion, finish: finish)
                    }
                }
            }
        }
    }

    func cancelAlarm(id: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.delegate.stopIfPlaying(alarmId: id)
            // Cancelling removes the primary, recurrence, and fallback requests.
            let identifiers = Self.requestIdentifiers(
                for: id,
                recurrenceWeekdays: WarmAlarmStore.shared.load(id: id)?.recurrenceWeekdays
            )
            WarmAlarmStore.shared.remove(id: id)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
        }
    }

    func cancelAllAlarms(completion: @escaping (Result<Void, Error>) -> Void) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.delegate.stopAllIfPlaying()
            WarmAlarmStore.shared.clear()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
        }
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
        notificationMutationQueue.enqueue { finish in
            UNUserNotificationCenter.current().getPendingNotificationRequests { pendingRequests in
                let pendingIdentifiers = Set(pendingRequests.map(\.identifier))
                guard Self.canConfigureKillWarning(
                    pendingIdentifiers: pendingIdentifiers,
                    limit: Self.pendingNotificationLimit
                ) else {
                    let error = PigeonError(
                        code: "pending-notification-limit",
                        message: "iOS has no available notification slot for the kill warning.",
                        details: nil
                    )
                    WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                    return
                }
                UserDefaults.standard.setValue(
                    ["title": title, "body": body],
                    forKey: Self.killWarningDefaultsKey
                )
                WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
            }
        }
    }

    func clearKillWarning(completion: @escaping (Result<Void, Error>) -> Void) {
        notificationMutationQueue.enqueue { finish in
            UserDefaults.standard.removeObject(forKey: Self.killWarningDefaultsKey)
            WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
        }
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
              let dict = UserDefaults.standard.dictionary(forKey: Self.killWarningDefaultsKey),
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
              let dict = UserDefaults.standard.dictionary(forKey: Self.killWarningDefaultsKey),
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
