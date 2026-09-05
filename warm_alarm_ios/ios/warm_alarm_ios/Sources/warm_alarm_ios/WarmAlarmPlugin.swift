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
        guard !requests.isEmpty else {
            completion(nil)
            return
        }
        let stateLock = NSLock()
        var remainingCount = requests.count
        var firstError: Error?
        var didSubmitAll = false
        var didComplete = false

        func completeIfReady() {
            stateLock.lock()
            guard didSubmitAll, remainingCount == 0, !didComplete else {
                stateLock.unlock()
                return
            }
            didComplete = true
            let error = firstError
            stateLock.unlock()

            if error != nil {
                rollback(identifiers)
            }
            completion(error)
        }

        for request in requests {
            add(request) { error in
                stateLock.lock()
                remainingCount -= 1
                if firstError == nil, let error {
                    firstError = error
                }
                stateLock.unlock()
                completeIfReady()
            }
        }

        stateLock.lock()
        didSubmitAll = true
        stateLock.unlock()
        completeIfReady()
    }
}

enum WarmAlarmSnoozeRegistration {
    static func perform(
        persistIntent: @escaping () -> Void,
        register: (@escaping (Error?) -> Void) -> Void,
        rollback: @escaping () -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        persistIntent()
        register { error in
            if let error {
                rollback()
            }
            WarmAlarmPlatformReply.performOnMain {
                completion(error)
            }
        }
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

    func enqueueOnMain(_ mutation: @escaping Mutation) {
        enqueue { finish in
            WarmAlarmPlatformReply.performOnMain {
                mutation(finish)
            }
        }
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
        prepare: @escaping (Alarm) -> Alarm = { $0 },
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
            recover(prepare(alarms[index])) { error in
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

private struct WarmAlarmOccurrenceMetadata {
    static let userInfoKey = "_warmAlarmOccurrenceV1"

    let token: String
    let ordinal: Int
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int
    let calendarIdentifier: String
    let floating: Bool
    let timeZoneIdentifier: String
    let primaryEpochMillis: Int64

    init?(dictionary: [String: Any]) {
        guard let token = dictionary["token"] as? String, !token.isEmpty,
              let ordinal = Self.int(dictionary["ordinal"]), (0...6).contains(ordinal),
              let year = Self.int(dictionary["year"]), year > 0,
              let month = Self.int(dictionary["month"]), (1...12).contains(month),
              let day = Self.int(dictionary["day"]), (1...31).contains(day),
              let hour = Self.int(dictionary["hour"]), (0...23).contains(hour),
              let minute = Self.int(dictionary["minute"]), (0...59).contains(minute),
              let second = Self.int(dictionary["second"]), (0...59).contains(second),
              let calendarIdentifier = dictionary["calendar"] as? String, calendarIdentifier == "gregorian",
              let floating = dictionary["floating"] as? Bool,
              let timeZoneIdentifier = dictionary["timeZone"] as? String, !timeZoneIdentifier.isEmpty,
              let primaryEpochMillis = Self.int64(dictionary["primaryEpochMillis"]) else {
            return nil
        }
        self.token = token
        self.ordinal = ordinal
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.calendarIdentifier = calendarIdentifier
        self.floating = floating
        self.timeZoneIdentifier = timeZoneIdentifier
        self.primaryEpochMillis = primaryEpochMillis
    }

    init?(
        token: String,
        ordinal: Int = 0,
        primaryAtMillis: Int64,
        calendar: Calendar,
        floating: Bool = true
    ) {
        let primaryDate = Date(timeIntervalSince1970: Double(primaryAtMillis) / 1_000)
        var metadataCalendar = Calendar(identifier: .gregorian)
        metadataCalendar.timeZone = calendar.timeZone
        let components = metadataCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: primaryDate
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }
        self.token = token
        self.ordinal = ordinal
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        calendarIdentifier = "gregorian"
        self.floating = floating
        timeZoneIdentifier = calendar.timeZone.identifier
        primaryEpochMillis = primaryAtMillis
    }

    func dictionary(ordinal: Int) -> [String: Any] {
        [
            "token": token,
            "ordinal": ordinal,
            "year": year,
            "month": month,
            "day": day,
            "hour": hour,
            "minute": minute,
            "second": second,
            "calendar": calendarIdentifier,
            "floating": floating,
            "timeZone": timeZoneIdentifier,
            "primaryEpochMillis": primaryEpochMillis,
        ]
    }

    func primaryDate(in calendar: Calendar) -> Date? {
        let epochDate = Date(timeIntervalSince1970: Double(primaryEpochMillis) / 1_000)
        if !floating {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
            var originalCalendar = Calendar(identifier: .gregorian)
            originalCalendar.timeZone = timeZone
            let epochComponents = originalCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: epochDate
            )
            guard epochComponents.year == year,
                  epochComponents.month == month,
                  epochComponents.day == day,
                  epochComponents.hour == hour,
                  epochComponents.minute == minute,
                  epochComponents.second == second else {
                return nil
            }
            return epochDate
        }
        var metadataCalendar = Calendar(identifier: .gregorian)
        metadataCalendar.timeZone = calendar.timeZone
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        if calendar.timeZone.identifier == timeZoneIdentifier {
            let epochComponents = metadataCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: epochDate
            )
            if epochComponents.year == year,
               epochComponents.month == month,
               epochComponents.day == day,
               epochComponents.hour == hour,
               epochComponents.minute == minute,
               epochComponents.second == second {
                return epochDate
            }
            return nil
        }
        guard let reconstructedDate = metadataCalendar.date(from: components) else {
            return nil
        }
        let reconstructedComponents = metadataCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reconstructedDate
        )
        guard reconstructedComponents.year == year,
              reconstructedComponents.month == month,
              reconstructedComponents.day == day,
              reconstructedComponents.hour == hour,
              reconstructedComponents.minute == minute,
              reconstructedComponents.second == second else {
            return nil
        }
        return reconstructedDate
    }

    func describesSameOccurrence(as other: WarmAlarmOccurrenceMetadata) -> Bool {
        token == other.token
            && year == other.year
            && month == other.month
            && day == other.day
            && hour == other.hour
            && minute == other.minute
            && second == other.second
            && floating == other.floating
            && calendarIdentifier == other.calendarIdentifier
            && timeZoneIdentifier == other.timeZoneIdentifier
            && primaryEpochMillis == other.primaryEpochMillis
    }

    func scopedToken(for primaryDate: Date) -> String {
        "\(token)#\(Int64(primaryDate.timeIntervalSince1970 * 1_000))"
    }

    private static func int(_ value: Any?) -> Int? {
        guard !(value is Bool) else { return nil }
        if let value = value as? Int { return value }
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else {
            return nil
        }
        return number.intValue
    }

    private static func int64(_ value: Any?) -> Int64? {
        guard !(value is Bool) else { return nil }
        if let value = value as? Int64 { return value }
        guard let number = value as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else {
            return nil
        }
        return number.int64Value
    }
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
            let storedSchedules = Array(WarmAlarmStore.shared.loadAll().values)
            guard !storedSchedules.isEmpty else {
                WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                return
            }
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { [weak self] pending in
                guard let self else {
                    finish()
                    return
                }
                let recurringSchedules = Self.migrateRecurringWallTimes(
                    storedSchedules,
                    pendingRequests: pending,
                    save: { WarmAlarmStore.shared.save($0) }
                )
                let migratedSchedules = Self.migrateOneShotFallbackAnchors(
                    recurringSchedules,
                    pendingRequests: pending,
                    save: { WarmAlarmStore.shared.save($0) }
                )
                let recoverableAlarms = Self.sortedRecoverableSchedules(
                    migratedSchedules,
                    nowMillis: nowMillis
                )
                guard !recoverableAlarms.isEmpty else {
                    WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                    return
                }
                self.recoverAlarms(
                    recoverableAlarms,
                    pendingRequests: pending,
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
        pendingRequests: [UNNotificationRequest],
        nowMillis: Int64,
        center: UNUserNotificationCenter,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let pendingIdentifiers = Set(pendingRequests.map(\.identifier))
        let requestGroups = alarms.map { schedule in
            let content = delegate.makeContent(from: schedule)
            return (
                schedule: schedule,
                content: content,
                requests: Self.makeRecoveryRequests(
                    for: schedule,
                    nowMillis: nowMillis,
                    pendingIdentifiers: pendingIdentifiers,
                    pendingRequests: pendingRequests,
                    content: content
                )
            )
        }
        let reservedSlotCount = Self.killWarningReservedSlotCount(
            isConfigured: Self.isKillWarningConfigured,
            pendingIdentifiers: pendingIdentifiers
        )
        guard let selection = Self.selectRecoveryRequestsWithinPendingLimit(
            requestGroups.map { $0.requests },
            pendingIdentifiers: pendingIdentifiers,
            reservedSlotCount: reservedSlotCount,
            limit: Self.pendingNotificationLimit
        ) else {
            let coreCount = Self.coreRequestCount(in: requestGroups.flatMap { $0.requests })
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
        var nextGroupIndex = 0
        var remainingRequestCount = selection.requests.count
        WarmAlarmRecovery.recoverAll(
            requestGroups,
            prepare: { group in
                let registrationNowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
                let remainingRequestGroups = requestGroups.dropFirst(nextGroupIndex).map { candidate in
                    Self.makeRecoveryRequests(
                        for: candidate.schedule,
                        nowMillis: registrationNowMillis,
                        pendingIdentifiers: pendingIdentifiers,
                        pendingRequests: pendingRequests,
                        content: candidate.content
                    )
                }
                nextGroupIndex += 1
                let requests = Self.selectNextRecoveryRequestsWithinLimit(
                    remainingRequestGroups,
                    remainingRequestCount: remainingRequestCount
                )
                return (schedule: group.schedule, content: group.content, requests: requests)
            },
            recover: { group, completion in
                guard !group.requests.isEmpty else {
                    completion(nil)
                    return
                }
                Self.addRequestsAtomically(
                    group.requests,
                    center: center
                ) { error in
                    if error == nil {
                        remainingRequestCount -= group.requests.count
                    }
                    completion(error)
                }
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

    static func migrateRecurringWallTimes(
        _ schedules: [WarmAlarmScheduleData],
        pendingRequests: [UNNotificationRequest],
        save: (WarmAlarmScheduleData) -> Void
    ) -> [WarmAlarmScheduleData] {
        schedules.map { schedule in
            guard schedule.recurrenceHour == nil || schedule.recurrenceMinute == nil,
                  let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty else {
                return schedule
            }
            let recurringIdentifiers = Set(weekdays.map { "\(schedule.id)#\($0)" })
            guard let trigger = pendingRequests.first(where: {
                recurringIdentifiers.contains($0.identifier)
                    && ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true
            })?.trigger as? UNCalendarNotificationTrigger,
                  let hour = trigger.dateComponents.hour,
                  let minute = trigger.dateComponents.minute else {
                return schedule
            }
            let migrated = schedule.withRecurrenceTime(hour: hour, minute: minute)
            save(migrated)
            return migrated
        }
    }

    static func migrateOneShotFallbackAnchors(
        _ schedules: [WarmAlarmScheduleData],
        pendingRequests: [UNNotificationRequest],
        calendar: Calendar = .current,
        save: (WarmAlarmScheduleData) -> Void
    ) -> [WarmAlarmScheduleData] {
        schedules.map { schedule in
            guard schedule.recurrenceWeekdays?.isEmpty ?? true,
                  schedule.activeSnoozeUntilMillis == nil else {
                return schedule
            }
            let primaryIdentifier = String(schedule.id)
            let matchingRequests = notificationRequests(for: schedule.id, in: pendingRequests)
            let metadataDate = occurrenceMetadata(for: schedule.id, in: matchingRequests)?.primaryDate(in: calendar)
            let primaryTriggerDate = matchingRequests.lazy.compactMap { request -> Date? in
                guard request.identifier == primaryIdentifier,
                      let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      !trigger.repeats else {
                    return nil
                }
                return calendar.date(from: trigger.dateComponents)
            }.first
            guard let primaryDate = metadataDate ?? primaryTriggerDate else {
                return schedule
            }
            let anchorMillis = Int64(primaryDate.timeIntervalSince1970 * 1_000)
            guard anchorMillis != schedule.fallbackAnchorMillis else {
                return schedule
            }
            let migrated = schedule.withOneShotAnchor(anchorMillis)
            save(migrated)
            return migrated
        }
    }

    static func sortedRecoverableSchedules(
        _ schedules: [WarmAlarmScheduleData],
        nowMillis: Int64,
        calendar: Calendar = .current
    ) -> [WarmAlarmScheduleData] {
        schedules
            .filter { shouldRecover(schedule: $0, nowMillis: nowMillis) }
            .sorted {
                let leftAnchor = recoveryOrderingAnchorMillis(
                    for: $0, nowMillis: nowMillis, calendar: calendar)
                let rightAnchor = recoveryOrderingAnchorMillis(
                    for: $1, nowMillis: nowMillis, calendar: calendar)
                return leftAnchor == rightAnchor ? $0.id < $1.id : leftAnchor < rightAnchor
            }
    }

    private static func recoveryOrderingAnchorMillis(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        calendar: Calendar
    ) -> Int64 {
        recoveryFallbackAnchorMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        ) ?? schedule.snapshotScheduledAtMillis(nowMillis: nowMillis, calendar: calendar)
    }

    static func makeRecoveryRequests(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        pendingIdentifiers: Set<String>,
        pendingRequests: [UNNotificationRequest] = [],
        content: UNNotificationContent,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        let usesRelativeFallbackTrigger = hasActiveSnoozeFallbacks(
            for: schedule,
            nowMillis: nowMillis
        )
        let fallbackAnchorMillis = recoveryFallbackAnchorMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        )
        let matchingPendingRequests = notificationRequests(for: schedule.id, in: pendingRequests)
        let primaryAtMillis = fallbackAnchorMillis
            ?? schedule.activeSnoozeUntilMillis
            ?? schedule.scheduledAtMillis
        let occurrenceToken = pendingOccurrenceSeriesToken(
            for: schedule.id,
            in: matchingPendingRequests
        ) ?? occurrenceSeriesToken(for: schedule.id)
        let chainMetadata = WarmAlarmOccurrenceMetadata(
            token: occurrenceToken,
            primaryAtMillis: primaryAtMillis,
            calendar: calendar,
            floating: !usesRelativeFallbackTrigger
        )
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

        if let anchor = fallbackAnchorMillis {
            expectedIdentifiers += fallbackIdentifiers(for: schedule.id).enumerated().compactMap { index, identifier in
                fallbackFireAtMillis(anchorMillis: anchor, index: index + 1) > nowMillis ? identifier : nil
            }
        }

        return deduplicatedRequests(
            expectedIdentifiers
                .filter { !pendingIdentifiers.contains($0) }
                .map { identifier in
                    let occurrenceMetadata = recoveryOccurrenceMetadata(
                        identifier: identifier,
                        schedule: schedule,
                        nowMillis: nowMillis,
                        calendar: calendar,
                        occurrenceToken: occurrenceToken,
                        chainMetadata: chainMetadata
                    )
                    let requestContent = contentWithOccurrenceMetadata(
                        content,
                        metadata: occurrenceMetadata,
                        ordinal: fallbackIndex(for: identifier, alarmId: schedule.id) ?? 0
                    )
                    return makeRecoveryRequest(
                        identifier: identifier,
                        schedule: schedule,
                        content: requestContent,
                        nowMillis: nowMillis,
                        calendar: calendar,
                        fallbackAnchorMillis: fallbackAnchorMillis,
                        usesRelativeFallbackTrigger: usesRelativeFallbackTrigger
                    )
                }
        )
    }

    private static func recoveryOccurrenceMetadata(
        identifier: String,
        schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        calendar: Calendar,
        occurrenceToken: String,
        chainMetadata: WarmAlarmOccurrenceMetadata?
    ) -> WarmAlarmOccurrenceMetadata? {
        guard let isoWeekday = recurringWeekday(for: identifier, alarmId: schedule.id) else {
            return chainMetadata
        }
        let scheduledDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1_000)
        let scheduledTime = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        guard let hour = schedule.recurrenceHour ?? scheduledTime.hour,
              let minute = schedule.recurrenceMinute ?? scheduledTime.minute else {
            return chainMetadata
        }
        var components = DateComponents()
        components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1_000)
        guard let primaryDate = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .strict,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return chainMetadata
        }
        return WarmAlarmOccurrenceMetadata(
            token: occurrenceToken,
            primaryAtMillis: Int64(primaryDate.timeIntervalSince1970 * 1_000),
            calendar: calendar
        )
    }

    static func selectNextRecoveryRequestsWithinLimit(
        _ requestGroups: [[UNNotificationRequest]],
        remainingRequestCount: Int
    ) -> [UNNotificationRequest] {
        guard let currentRequests = requestGroups.first else { return [] }
        let futureCoreCount = coreRequestCount(in: requestGroups.dropFirst().flatMap { $0 })
        let currentCoreRequests = currentRequests.filter { !isFallbackIdentifier($0.identifier) }
        let currentFallbackRequests = currentRequests.filter { isFallbackIdentifier($0.identifier) }
        let fallbackCount = max(0, remainingRequestCount - futureCoreCount - currentCoreRequests.count)
        return currentCoreRequests + Array(currentFallbackRequests.prefix(fallbackCount))
    }

    private static func makeRecoveryRequest(
        identifier: String,
        schedule: WarmAlarmScheduleData,
        content: UNNotificationContent,
        nowMillis: Int64,
        calendar: Calendar,
        fallbackAnchorMillis: Int64?,
        usesRelativeFallbackTrigger: Bool
    ) -> UNNotificationRequest {
        let recoveryFallbackIndex = fallbackIndex(for: identifier, alarmId: schedule.id)
        let fireAtMillis: Int64
        if let recoveryFallbackIndex, let anchor = fallbackAnchorMillis {
            fireAtMillis = fallbackFireAtMillis(anchorMillis: anchor, index: recoveryFallbackIndex)
            if usesRelativeFallbackTrigger {
                let delay = max(1.0, Double(fireAtMillis - nowMillis) / 1_000.0)
                return UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                )
            }
        } else if identifier == String(schedule.id),
                  let activeSnoozeUntilMillis = schedule.activeSnoozeUntilMillis {
            let delay = max(1.0, Double(activeSnoozeUntilMillis - nowMillis) / 1_000.0)
            return UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            )
        } else {
            fireAtMillis = WarmAlarmRecurrence.recoveryFireAtMillis(
                identifier: identifier,
                scheduledAtMillis: schedule.scheduledAtMillis,
                activeSnoozeUntilMillis: schedule.activeSnoozeUntilMillis,
                nowMillis: nowMillis
            )
        }
        let fireDate = Date(timeIntervalSince1970: Double(fireAtMillis) / 1000.0)
        if recoveryFallbackIndex == nil,
           let separator = identifier.lastIndex(of: "#"),
           let isoWeekday = Int64(identifier[identifier.index(after: separator)...]) {
            let time = calendar.dateComponents([.hour, .minute], from: fireDate)
            var components = DateComponents()
            components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
            components.hour = schedule.recurrenceHour ?? time.hour
            components.minute = schedule.recurrenceMinute ?? time.minute
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
        let occurrenceMetadata = WarmAlarmOccurrenceMetadata(
            token: occurrenceSeriesToken(for: schedule.id),
            primaryAtMillis: fallbackAnchorMillis,
            calendar: calendar
        )
        if let weekdays = schedule.recurrence?.weekdays, !weekdays.isEmpty {
            let time = calendar.dateComponents([.hour, .minute], from: fireDate)
            let requestedDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let requestedAtMillis = calendar.date(from: requestedDateComponents)
                .map { Int64($0.timeIntervalSince1970 * 1_000) }
                ?? schedule.scheduledAtMillis
            let recurringOccurrenceMetadata = WarmAlarmOccurrenceMetadata(
                token: occurrenceSeriesToken(for: schedule.id),
                primaryAtMillis: requestedAtMillis,
                calendar: calendar
            )
            let recurringRequests = weekdays.map { iso in
                var components = DateComponents()
                components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: iso)
                components.hour = time.hour
                components.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                return UNNotificationRequest(
                    identifier: "\(schedule.id)#\(iso)",
                    content: contentWithOccurrenceMetadata(
                        content,
                        metadata: recurringOccurrenceMetadata,
                        ordinal: 0
                    ),
                    trigger: trigger
                )
            }
            return recurringRequests + makeFallbackRequests(
                alarmId: schedule.id,
                content: content,
                occurrenceMetadata: occurrenceMetadata,
                anchorMillis: fallbackAnchorMillis,
                calendar: calendar
            )
        }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let primaryRequest = UNNotificationRequest(
            identifier: String(schedule.id),
            content: contentWithOccurrenceMetadata(content, metadata: occurrenceMetadata, ordinal: 0),
            trigger: trigger
        )
        return [primaryRequest] + makeFallbackRequests(
            alarmId: schedule.id,
            content: content,
            occurrenceMetadata: occurrenceMetadata,
            anchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )
    }

    static func makeSnoozeRequests(
        for schedule: WarmAlarmScheduleData,
        fireAtMillis: Int64,
        nowMillis: Int64,
        content: UNNotificationContent
    ) -> [UNNotificationRequest] {
        let delay = max(1.0, Double(fireAtMillis - nowMillis) / 1000.0)
        let occurrenceMetadata = WarmAlarmOccurrenceMetadata(
            token: occurrenceSeriesToken(for: schedule.id),
            primaryAtMillis: fireAtMillis,
            calendar: .current,
            floating: false
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let primaryRequest = UNNotificationRequest(
            identifier: String(schedule.id),
            content: contentWithOccurrenceMetadata(content, metadata: occurrenceMetadata, ordinal: 0),
            trigger: trigger
        )
        let fallbackRequests = fallbackIdentifiers(for: schedule.id).enumerated().map { index, identifier in
            let fallbackDelay = delay + Double(index + 1) * Double(fallbackIntervalMillis) / 1_000.0
            let fallbackTrigger = UNTimeIntervalNotificationTrigger(timeInterval: fallbackDelay, repeats: false)
            return UNNotificationRequest(
                identifier: identifier,
                content: contentWithOccurrenceMetadata(content, metadata: occurrenceMetadata, ordinal: index + 1),
                trigger: fallbackTrigger
            )
        }
        return [primaryRequest] + fallbackRequests
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

    private static func notificationRequests(
        for alarmId: Int64,
        in requests: [UNNotificationRequest]
    ) -> [UNNotificationRequest] {
        let identifier = String(alarmId)
        let childPrefix = "\(alarmId)#"
        return requests.filter {
            $0.identifier == identifier || $0.identifier.hasPrefix(childPrefix)
        }
    }

    private static func occurrenceMetadata(from content: UNNotificationContent) -> WarmAlarmOccurrenceMetadata? {
        guard let dictionary = content.userInfo[WarmAlarmOccurrenceMetadata.userInfoKey] as? [String: Any] else {
            return nil
        }
        return WarmAlarmOccurrenceMetadata(dictionary: dictionary)
    }

    private static func occurrenceMetadata(
        for alarmId: Int64,
        in requests: [UNNotificationRequest]
    ) -> WarmAlarmOccurrenceMetadata? {
        let requestsWithMetadata = notificationRequests(for: alarmId, in: requests).filter {
            $0.content.userInfo[WarmAlarmOccurrenceMetadata.userInfoKey] != nil
        }
        guard !requestsWithMetadata.isEmpty else { return nil }

        var sharedMetadata: WarmAlarmOccurrenceMetadata?
        for request in requestsWithMetadata {
            guard let metadata = occurrenceMetadata(from: request.content),
                  metadata.ordinal == (fallbackIndex(for: request.identifier, alarmId: alarmId) ?? 0) else {
                return nil
            }
            if let sharedMetadata,
               !sharedMetadata.describesSameOccurrence(as: metadata) {
                return nil
            }
            sharedMetadata = metadata
        }
        return sharedMetadata
    }

    private static func pendingOccurrenceSeriesToken(
        for alarmId: Int64,
        in requests: [UNNotificationRequest]
    ) -> String? {
        let requestsWithMetadata = notificationRequests(for: alarmId, in: requests).filter {
            $0.content.userInfo[WarmAlarmOccurrenceMetadata.userInfoKey] != nil
        }
        guard !requestsWithMetadata.isEmpty else { return nil }

        var sharedToken: String?
        for request in requestsWithMetadata {
            guard let metadata = occurrenceMetadata(from: request.content),
                  metadata.ordinal == (fallbackIndex(for: request.identifier, alarmId: alarmId) ?? 0) else {
                return nil
            }
            if let sharedToken, sharedToken != metadata.token {
                return nil
            }
            sharedToken = metadata.token
        }
        return sharedToken
    }

    private static func occurrenceSeriesToken(for alarmId: Int64) -> String {
        "warm-alarm-v1:\(alarmId)"
    }

    private static func contentWithOccurrenceMetadata(
        _ content: UNNotificationContent,
        metadata: WarmAlarmOccurrenceMetadata?,
        ordinal: Int
    ) -> UNNotificationContent {
        guard let metadata,
              let copy = content.mutableCopy() as? UNMutableNotificationContent else {
            return content
        }
        var userInfo = copy.userInfo
        userInfo[WarmAlarmOccurrenceMetadata.userInfoKey] = metadata.dictionary(ordinal: ordinal)
        copy.userInfo = userInfo
        return copy
    }

    static func foregroundOccurrenceToken(
        content: UNNotificationContent? = nil,
        identifier: String,
        alarmId: Int64,
        deliveredAtMillis: Int64,
        calendar: Calendar = .current,
        schedule: WarmAlarmScheduleData? = nil
    ) -> String {
        if let content,
           let metadata = occurrenceMetadata(from: content),
           let metadataPrimaryDate = metadata.primaryDate(in: calendar) {
            if let isoWeekday = recurringWeekday(for: identifier, alarmId: alarmId) {
                let deliveredDate = Date(timeIntervalSince1970: Double(deliveredAtMillis) / 1_000)
                var components = DateComponents()
                components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
                components.hour = metadata.hour
                components.minute = metadata.minute
                components.second = metadata.second
                let occurrenceDate = calendar.nextDate(
                    after: deliveredDate.addingTimeInterval(0.001),
                    matching: components,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .backward
                ) ?? metadataPrimaryDate
                return metadata.scopedToken(for: occurrenceDate)
            }
            return metadata.scopedToken(for: metadataPrimaryDate)
        }
        if let schedule {
            let seriesToken = occurrenceSeriesToken(for: alarmId)
            if let isoWeekday = recurringWeekday(for: identifier, alarmId: alarmId),
               let hour = schedule.recurrenceHour,
               let minute = schedule.recurrenceMinute {
                let deliveredDate = Date(timeIntervalSince1970: Double(deliveredAtMillis) / 1_000)
                var components = DateComponents()
                components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
                components.hour = hour
                components.minute = minute
                components.second = 0
                if let occurrenceDate = calendar.nextDate(
                    after: deliveredDate.addingTimeInterval(0.001),
                    matching: components,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .backward
                ) {
                    return "\(seriesToken)#\(Int64(occurrenceDate.timeIntervalSince1970 * 1_000))"
                }
            }
            let primaryAtMillis = schedule.fallbackAnchorMillis
                ?? schedule.activeSnoozeUntilMillis
                ?? schedule.scheduledAtMillis
            return "\(seriesToken)#\(primaryAtMillis)"
        }
        guard let index = fallbackIndex(for: identifier, alarmId: alarmId) else {
            return String(deliveredAtMillis)
        }
        return String(deliveredAtMillis - Int64(index) * fallbackIntervalMillis)
    }

    static func actionOccurrenceLowerBound(
        for schedule: WarmAlarmScheduleData,
        content: UNNotificationContent? = nil,
        nowMillis: Int64,
        calendar: Calendar = .current
    ) -> Int64? {
        if let content,
           let notificationOccurrenceMillis = floatingOneShotOccurrenceMillis(
               for: schedule,
               content: content,
               calendar: calendar
           ) {
            return notificationOccurrenceMillis
        }
        let fallbackAnchorMillis = recoveryFallbackAnchorMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        )
        let recurrenceOccurrenceMillis = latestRecurrenceOccurrenceMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        )
        return [fallbackAnchorMillis, recurrenceOccurrenceMillis].compactMap { $0 }.max()
    }

    private static func floatingOneShotOccurrenceMillis(
        for schedule: WarmAlarmScheduleData,
        content: UNNotificationContent,
        calendar: Calendar
    ) -> Int64? {
        guard schedule.recurrenceWeekdays?.isEmpty != false,
              let metadata = occurrenceMetadata(from: content),
              metadata.floating,
              metadata.token == occurrenceSeriesToken(for: schedule.id),
              metadata.primaryEpochMillis == schedule.oneShotOccurrenceEpochMillis,
              let occurrenceDate = metadata.primaryDate(in: calendar) else {
            return nil
        }
        return Int64(occurrenceDate.timeIntervalSince1970 * 1_000)
    }

    private static func latestRecurrenceOccurrenceMillis(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        calendar: Calendar
    ) -> Int64? {
        guard let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty,
              let hour = schedule.recurrenceHour,
              let minute = schedule.recurrenceMinute else {
            return nil
        }
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1_000)
        return weekdays.compactMap { isoWeekday -> Date? in
            var components = DateComponents()
            components.weekday = WarmAlarmRecurrence.appleWeekday(fromIso: isoWeekday)
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: now.addingTimeInterval(0.001),
                matching: components,
                matchingPolicy: .strict,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        }.max().map { Int64($0.timeIntervalSince1970 * 1_000) }
    }

    private static func recurringWeekday(for identifier: String, alarmId: Int64) -> Int64? {
        let prefix = "\(alarmId)#"
        guard identifier.hasPrefix(prefix),
              !identifier.contains("#fallback#"),
              let isoWeekday = Int64(identifier.dropFirst(prefix.count)),
              (1...7).contains(isoWeekday) else {
            return nil
        }
        return isoWeekday
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

    private static func hasActiveSnoozeFallbacks(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64
    ) -> Bool {
        guard schedule.activeSnoozeUntilMillis != nil,
              let fallbackAnchorMillis = schedule.fallbackAnchorMillis else {
            return false
        }
        return fallbackFireAtMillis(anchorMillis: fallbackAnchorMillis, index: fallbackCount) > nowMillis
    }

    private static func recoveryFallbackAnchorMillis(
        for schedule: WarmAlarmScheduleData,
        nowMillis: Int64,
        calendar: Calendar
    ) -> Int64? {
        guard let persistedAnchorMillis = schedule.fallbackAnchorMillis else { return nil }
        guard !hasActiveSnoozeFallbacks(for: schedule, nowMillis: nowMillis),
              let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty,
              let hour = schedule.recurrenceHour,
              let minute = schedule.recurrenceMinute else {
            return persistedAnchorMillis
        }
        if schedule.activeSnoozeUntilMillis == nil {
            let persistedAnchorDate = Date(timeIntervalSince1970: Double(persistedAnchorMillis) / 1_000)
            let persistedTime = calendar.dateComponents([.weekday, .hour, .minute], from: persistedAnchorDate)
            let appleWeekdays = Set(weekdays.map(WarmAlarmRecurrence.appleWeekday))
            let persistedWeekdayMatches = persistedTime.weekday.map(appleWeekdays.contains) ?? false
            if persistedWeekdayMatches, persistedTime.hour == hour, persistedTime.minute == minute {
                return persistedAnchorMillis
            }
        }
        let fallbackWindowMillis = Int64(fallbackCount) * fallbackIntervalMillis
        return WarmAlarmRecurrence.nextOccurrenceMillis(
            hour: hour,
            minute: minute,
            weekdays: weekdays,
            afterMillis: nowMillis - fallbackWindowMillis,
            calendar: calendar
        ) ?? persistedAnchorMillis
    }

    private static func makeFallbackRequests(
        alarmId: Int64,
        content: UNNotificationContent,
        occurrenceMetadata: WarmAlarmOccurrenceMetadata?,
        anchorMillis: Int64,
        calendar: Calendar
    ) -> [UNNotificationRequest] {
        fallbackIdentifiers(for: alarmId).enumerated().map { index, identifier in
            let scheduledAtMillis = fallbackFireAtMillis(anchorMillis: anchorMillis, index: index + 1)
            let requestDate = Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1000.0)
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: requestDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(
                identifier: identifier,
                content: contentWithOccurrenceMetadata(
                    content,
                    metadata: occurrenceMetadata,
                    ordinal: index + 1
                ),
                trigger: trigger
            )
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

    static func completePendingLimitFailure(
        alarmId: Int64,
        error: Error,
        emitFailure: @escaping (Int64, String) -> Void,
        completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void,
        finish: @escaping () -> Void
    ) {
        emitFailure(alarmId, error.localizedDescription)
        WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
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
                    Self.completePendingLimitFailure(
                        alarmId: schedule.id,
                        error: error,
                        emitFailure: self.delegate.emitFailure,
                        completion: completion,
                        finish: finish
                    )
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
