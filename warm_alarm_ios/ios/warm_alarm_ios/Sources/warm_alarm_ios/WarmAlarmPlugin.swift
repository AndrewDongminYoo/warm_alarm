import AVFAudio
import CoreFoundation
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
        register: (@escaping (Error?, Bool) -> Void) -> Void,
        rollback: @escaping (Bool, @escaping (Error?) -> Void) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        persistIntent()
        register { error, didSubmitRequests in
            if let error {
                rollback(didSubmitRequests) { rollbackError in
                    WarmAlarmPlatformReply.performOnMain {
                        completion(rollbackError ?? error)
                    }
                }
                return
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
        let sameWallTime = token == other.token
            && year == other.year
            && month == other.month
            && day == other.day
            && hour == other.hour
            && minute == other.minute
            && second == other.second
            && floating == other.floating
            && calendarIdentifier == other.calendarIdentifier
        guard sameWallTime else { return false }
        if !floating {
            return timeZoneIdentifier == other.timeZoneIdentifier
                && primaryEpochMillis == other.primaryEpochMillis
        }
        return timeZoneIdentifier != other.timeZoneIdentifier
            || primaryEpochMillis == other.primaryEpochMillis
    }

    func hasConsistentPrimaryEpoch() -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = timeZone
        return primaryDate(in: sourceCalendar) != nil
    }

    func scopedToken(for primaryDate: Date) -> String {
        "\(token)#\(Int64(primaryDate.timeIntervalSince1970 * 1_000))"
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else {
            return nil
        }
        return number.intValue
    }

    private static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue else {
            return nil
        }
        return number.int64Value
    }
}

class WarmAlarmNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    private final class WeakDelegateReference {
        weak var delegate: WarmAlarmNotificationCenterDelegate?

        init(_ delegate: WarmAlarmNotificationCenterDelegate) {
            self.delegate = delegate
        }
    }

    private static let installationLock = NSLock()
    private let warmAlarmDelegate: WarmAlarmDelegate
    private let previousWarmAlarmDelegates: [WeakDelegateReference]
    weak var forwardingDelegate: UNUserNotificationCenterDelegate?

    init(
        warmAlarmDelegate: WarmAlarmDelegate,
        forwardingDelegate: UNUserNotificationCenterDelegate?,
        previousWarmAlarmDelegate: WarmAlarmNotificationCenterDelegate? = nil
    ) {
        self.warmAlarmDelegate = warmAlarmDelegate
        self.forwardingDelegate = forwardingDelegate
        previousWarmAlarmDelegates = previousWarmAlarmDelegate.map {
            [WeakDelegateReference($0)] + $0.previousWarmAlarmDelegates
        } ?? []
    }

    var restorationDelegate: UNUserNotificationCenterDelegate? {
        previousWarmAlarmDelegates.lazy.compactMap(\.delegate).first ?? forwardingDelegate
    }

    static func install(
        warmAlarmDelegate: WarmAlarmDelegate,
        on notificationCenter: UNUserNotificationCenter
    ) -> WarmAlarmNotificationCenterDelegate {
        installationLock.lock()
        defer { installationLock.unlock() }

        let installedDelegate = notificationCenter.delegate
        let previousWarmAlarmDelegate = installedDelegate as? WarmAlarmNotificationCenterDelegate
        let forwardingDelegate = previousWarmAlarmDelegate?.forwardingDelegate ?? installedDelegate
        // Firebase Messaging keeps Flutter lifecycle fan-out only when this conformance survives delegate replacement.
        let delegate = if forwardingDelegate is FlutterAppLifeCycleProvider {
            WarmAlarmFlutterNotificationCenterDelegate(
                warmAlarmDelegate: warmAlarmDelegate,
                forwardingDelegate: forwardingDelegate,
                previousWarmAlarmDelegate: previousWarmAlarmDelegate
            )
        } else {
            WarmAlarmNotificationCenterDelegate(
                warmAlarmDelegate: warmAlarmDelegate,
                forwardingDelegate: forwardingDelegate,
                previousWarmAlarmDelegate: previousWarmAlarmDelegate
            )
        }
        notificationCenter.delegate = delegate
        return delegate
    }

    func uninstall(from notificationCenter: UNUserNotificationCenter) {
        Self.installationLock.lock()
        defer { Self.installationLock.unlock() }

        guard notificationCenter.delegate === self else { return }
        notificationCenter.delegate = restorationDelegate
    }

    func target(for content: UNNotificationContent) -> UNUserNotificationCenterDelegate? {
        if content.categoryIdentifier == WarmAlarmDelegate.categoryIdentifier {
            return warmAlarmDelegate
        }
        return forwardingDelegate
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let target = target(for: notification.request.content),
              target.userNotificationCenter?(
                  center,
                  willPresent: notification,
                  withCompletionHandler: completionHandler
              ) != nil else {
            completionHandler([])
            return
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let target = target(for: response.notification.request.content),
              target.userNotificationCenter?(
                  center,
                  didReceive: response,
                  withCompletionHandler: completionHandler
              ) != nil else {
            completionHandler()
            return
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        forwardingDelegate?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}

final class WarmAlarmFlutterNotificationCenterDelegate: WarmAlarmNotificationCenterDelegate, FlutterAppLifeCycleProvider {
    func add(_ delegate: FlutterApplicationLifeCycleDelegate) {
        (forwardingDelegate as? FlutterAppLifeCycleProvider)?.add(delegate)
    }
}

enum WarmAlarmAppleSchedulingBackend {
    case alarmKit
    case userNotifications
}

private struct WarmAlarmNotificationSchedulingOutcome {
    let didSchedule: Bool
    let warning: WarmAlarmWarningWire?
}

struct WarmAlarmPermissionSnapshot {
    let permissionState: WarmAlarmPermissionStateWire
    let readiness: WarmAlarmReadinessWire
}

struct WarmAlarmAlarmKitInitializationWork {
    let alarmKitManaged: [WarmAlarmScheduleData]
    let notificationRecovery: [WarmAlarmScheduleData]
    let expiredAlarmIDs: [Int64]
}

struct WarmAlarmAlarmKitObservationUpdate {
    let previous: WarmAlarmAlarmKitSnapshot
    let suppressedTerminalIDs: Set<UUID>
}

final class WarmAlarmAlarmKitObservationState: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = WarmAlarmAlarmKitSnapshot(states: [:])
    private var locallyMutatingIDs = Set<UUID>()

    func update(_ next: WarmAlarmAlarmKitSnapshot) -> WarmAlarmAlarmKitObservationUpdate {
        lock.lock()
        defer { lock.unlock() }
        let previous = snapshot
        snapshot = next
        var suppressedTerminalIDs = Set<UUID>()
        for id in locallyMutatingIDs {
            let previousState = previous.states[id]
            let currentState = next.states[id]
            if previousState == .alerting || previousState == .countdown || previousState == .paused,
               currentState == nil || currentState == .scheduled {
                suppressedTerminalIDs.insert(id)
            }
        }
        locallyMutatingIDs.subtract(suppressedTerminalIDs)
        return WarmAlarmAlarmKitObservationUpdate(
            previous: previous,
            suppressedTerminalIDs: suppressedTerminalIDs
        )
    }

    func beginMutation(ids: some Sequence<UUID>) {
        lock.lock()
        locallyMutatingIDs.formUnion(ids)
        lock.unlock()
    }

    func finishMutation(ids: some Sequence<UUID>) {
        lock.lock()
        locallyMutatingIDs.subtract(ids)
        lock.unlock()
    }

    func finishSchedule(id: UUID) {
        lock.lock()
        locallyMutatingIDs.remove(id)
        var states = snapshot.states
        states[id] = .scheduled
        var nextTriggerDates = snapshot.nextTriggerDates
        nextTriggerDates.removeValue(forKey: id)
        snapshot = WarmAlarmAlarmKitSnapshot(
            states: states,
            nextTriggerDates: nextTriggerDates
        )
        lock.unlock()
    }
}

public class WarmAlarmPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate, WarmAlarmApi {
    private let delegate: WarmAlarmDelegate
    private let notificationMutationQueue: WarmAlarmMutationQueue
    private let notificationCenter: UNUserNotificationCenter
    private let notificationCenterDelegate: WarmAlarmNotificationCenterDelegate
    private let alarmKitBackend: WarmAlarmAlarmKitScheduling?
    private let alarmKitUsageDescription: String?
    private let alarmKitLiveActivityEnabled: Bool
    private static let killWarningNotifId = "warm_alarm_kill_warning_notif"
    private static let killWarningDefaultsKey = "warm_alarm_kill_warning"
    private static let fallbackCount = 6
    private static let fallbackIntervalMillis: Int64 = 30_000
    private static let pendingNotificationLimit = 64
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let alarmKitObservationState = WarmAlarmAlarmKitObservationState()

    static func schedulingBackend(
        alarmKitAvailable: Bool,
        alarmKitUsageDescription: String?,
        authorizationState: WarmAlarmAlarmKitAuthorization
    ) -> WarmAlarmAppleSchedulingBackend {
        guard alarmKitAvailable,
              let alarmKitUsageDescription,
              !alarmKitUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              authorizationState != .denied
        else {
            return .userNotifications
        }
        return .alarmKit
    }

    static func canUseAlarmKit(
        for plan: WarmAlarmAlarmKitPlan,
        liveActivityConfigured: Bool
    ) -> Bool {
        plan.snoozeDuration == nil || liveActivityConfigured
    }

    init(
        delegate: WarmAlarmDelegate,
        notificationMutationQueue: WarmAlarmMutationQueue,
        notificationCenter: UNUserNotificationCenter,
        notificationCenterDelegate: WarmAlarmNotificationCenterDelegate,
        alarmKitBackend: WarmAlarmAlarmKitScheduling? = WarmAlarmAlarmKitBackendFactory.make(),
        alarmKitUsageDescription: String? = Bundle.main.object(
            forInfoDictionaryKey: "NSAlarmKitUsageDescription"
        ) as? String,
        alarmKitLiveActivityEnabled: Bool = Bundle.main.object(
            forInfoDictionaryKey: "WarmAlarmAlarmKitLiveActivityEnabled"
        ) as? Bool ?? false
    ) {
        self.delegate = delegate
        self.notificationMutationQueue = notificationMutationQueue
        self.notificationCenter = notificationCenter
        self.notificationCenterDelegate = notificationCenterDelegate
        self.alarmKitBackend = alarmKitBackend
        self.alarmKitUsageDescription = alarmKitUsageDescription
        self.alarmKitLiveActivityEnabled = alarmKitLiveActivityEnabled
        super.init()
        setupLifecycleObservers()
        setupAlarmKitObserver()
    }

    deinit {
        alarmKitBackend?.stopObserving()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationCenterDelegate.uninstall(from: notificationCenter)
    }

    private func setupAlarmKitObserver() {
        guard let alarmKitBackend,
              let alarmKitUsageDescription,
              !alarmKitUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        alarmKitBackend.observe { [weak self] snapshot in
            self?.handleAlarmKitUpdate(snapshot)
        }
    }

    private func handleAlarmKitUpdate(_ snapshot: WarmAlarmAlarmKitSnapshot) {
        let observationUpdate = alarmKitObservationState.update(snapshot)
        let previous = observationUpdate.previous
        let schedules = WarmAlarmStore.shared.loadAll().values
        for schedule in schedules where schedule.alarmKitManaged {
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: schedule.id)
            let previousState = previous.states[alarmKitID]
            let currentState = snapshot.states[alarmKitID]
            if observationUpdate.suppressedTerminalIDs.contains(alarmKitID) {
                continue
            }
            if previousState == .alerting,
               currentState == .countdown || currentState == .paused {
                delegate.handleAlarmKitSnooze(
                    schedule: schedule,
                    fireAtMillis: snapshot.nextTriggerDates[alarmKitID].map {
                        Int64($0.timeIntervalSince1970 * 1_000)
                    }
                )
            } else if currentState == .countdown,
                      let fireAtMillis = snapshot.nextTriggerDates[alarmKitID].map({
                          Int64($0.timeIntervalSince1970 * 1_000)
                      }) {
                if schedule.alarmKitSnoozeObserved {
                    delegate.synchronizeAlarmKitSnooze(
                        schedule: schedule,
                        fireAtMillis: fireAtMillis
                    )
                } else {
                    delegate.handleAlarmKitSnooze(
                        schedule: schedule,
                        fireAtMillis: fireAtMillis
                    )
                }
            } else if currentState == .paused, !schedule.alarmKitSnoozeObserved {
                delegate.handleAlarmKitSnooze(schedule: schedule, fireAtMillis: nil)
            } else if (previousState == .alerting || previousState == .countdown || previousState == .paused),
                      currentState == nil || currentState == .scheduled {
                delegate.handleAlarmKitStop(schedule: schedule)
            } else if previousState != .alerting, currentState == .alerting {
                delegate.handleAlarmKitAlert(schedule: schedule)
            }
        }
    }

    private func replayUnobservedAlarmKitSnoozes(from snapshot: WarmAlarmAlarmKitSnapshot) {
        for schedule in WarmAlarmStore.shared.loadAll().values where !schedule.alarmKitSnoozeObserved {
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: schedule.id)
            guard snapshot.states[alarmKitID] == .countdown || snapshot.states[alarmKitID] == .paused else {
                continue
            }
            delegate.handleAlarmKitSnooze(
                schedule: schedule,
                fireAtMillis: snapshot.nextTriggerDates[alarmKitID].map {
                    Int64($0.timeIntervalSince1970 * 1_000)
                }
            )
        }
    }

    private func beginAlarmKitMutation(ids: some Sequence<UUID>) {
        alarmKitObservationState.beginMutation(ids: ids)
    }

    private func finishAlarmKitMutation(ids: some Sequence<UUID>) {
        alarmKitObservationState.finishMutation(ids: ids)
    }

    private func finishAlarmKitSchedule(id: UUID) {
        alarmKitObservationState.finishSchedule(id: id)
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
        let eventsChannel = FlutterBasicMessageChannel(
            name: "dev.flutter.pigeon.warm_alarm.WarmAlarmEventsApi.emitEvent",
            binaryMessenger: binaryMessenger,
            codec: MessagesPigeonCodec.shared
        )
        eventsChannel.resizeBuffer(64)
        let eventsApi = WarmAlarmEventsApi(binaryMessenger: binaryMessenger)
        // ponytail: serializes all Apple notification mutations; split by alarm ID only if contention is measured.
        let notificationMutationQueue = WarmAlarmMutationQueue(label: "warm_alarm.notification_mutation")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: notificationMutationQueue
        )
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: delegate,
            on: notificationCenter
        )
        let instance = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: notificationMutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: WarmAlarmAlarmKitBackendFactory.make(),
            alarmKitUsageDescription: Bundle.main.object(
                forInfoDictionaryKey: "NSAlarmKitUsageDescription"
            ) as? String,
            alarmKitLiveActivityEnabled: Bundle.main.object(
                forInfoDictionaryKey: "WarmAlarmAlarmKitLiveActivityEnabled"
            ) as? Bool ?? false
        )

        WarmAlarmDelegate.registerCategories()
        WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
        registrar.publish(instance)
    }

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
        guard let response = connectionOptions?.notificationResponse else { return false }
        return delegate.handleNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            deliveredIdentifier: response.notification.request.identifier,
            content: response.notification.request.content,
            deliveredAtMillis: Int64(response.notification.date.timeIntervalSince1970 * 1_000),
            completionHandler: {}
        )
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
            let backendChoice = Self.schedulingBackend(
                alarmKitAvailable: self.alarmKitBackend != nil,
                alarmKitUsageDescription: self.alarmKitUsageDescription,
                authorizationState: self.alarmKitBackend?.authorizationState ?? .denied
            )
            guard backendChoice == .alarmKit, let alarmKitBackend = self.alarmKitBackend else {
                let alarmKitManagedSchedules = storedSchedules.filter { $0.alarmKitManaged }
                guard let alarmKitBackend = self.alarmKitBackend,
                      !alarmKitManagedSchedules.isEmpty else {
                    let notificationSchedules = storedSchedules.map { schedule in
                        let updated = schedule.withAlarmKitManaged(false)
                        if schedule.alarmKitManaged { WarmAlarmStore.shared.save(updated) }
                        return updated
                    }
                    self.initializeNotificationState(
                        schedules: notificationSchedules,
                        alarmKitManaged: [],
                        nowMillis: nowMillis,
                        completion: completion,
                        finish: finish
                    )
                    return
                }
                self.beginAlarmKitMutation(ids: alarmKitManagedSchedules.map {
                    WarmAlarmAlarmKitPlan.id(for: $0.id)
                })
                WarmAlarmRecovery.recoverAll(
                    alarmKitManagedSchedules.map { WarmAlarmAlarmKitPlan.id(for: $0.id) },
                    recover: alarmKitBackend.cancel
                ) { result in
                    switch result {
                    case let .failure(error):
                        self.finishAlarmKitMutation(ids: alarmKitManagedSchedules.map {
                            WarmAlarmAlarmKitPlan.id(for: $0.id)
                        })
                        WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                    case .success:
                        let notificationSchedules = storedSchedules.map { schedule in
                            let updated = schedule.withAlarmKitManaged(false)
                            if schedule.alarmKitManaged { WarmAlarmStore.shared.save(updated) }
                            return updated
                        }
                        self.finishAlarmKitMutation(ids: alarmKitManagedSchedules.map {
                            WarmAlarmAlarmKitPlan.id(for: $0.id)
                        })
                        self.initializeNotificationState(
                            schedules: notificationSchedules,
                            alarmKitManaged: [],
                            nowMillis: nowMillis,
                            completion: completion,
                            finish: finish
                        )
                    }
                }
                return
            }
            alarmKitBackend.snapshot { [weak self] result in
                guard let self else {
                    finish()
                    return
                }
                switch result {
                case let .failure(error):
                    NSLog(
                        "[warm_alarm_ios] backend=alarmKit initializationInventoryError=%@",
                        error.localizedDescription
                    )
                    WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                case let .success(snapshot):
                    let incompatibleIDs = Self.incompatibleAlarmKitScheduleIDs(
                        schedules: storedSchedules,
                        snapshot: snapshot,
                        liveActivityConfigured: self.alarmKitLiveActivityEnabled
                    )
                    self.beginAlarmKitMutation(ids: incompatibleIDs)
                    WarmAlarmRecovery.recoverAll(
                        incompatibleIDs,
                        recover: alarmKitBackend.cancel
                    ) { cancellationResult in
                        if case let .failure(error) = cancellationResult {
                            self.finishAlarmKitMutation(ids: incompatibleIDs)
                            WarmAlarmPlatformReply.complete(
                                .failure(error), completion: completion, finish: finish
                            )
                            return
                        }
                        let reconciledSnapshot = snapshot.removing(ids: Set(incompatibleIDs))
                        self.replayUnobservedAlarmKitSnoozes(from: reconciledSnapshot)
                        let currentSchedules = Array(WarmAlarmStore.shared.loadAll().values)
                        switch Self.resolveAlarmKitInitializationWork(
                            schedules: currentSchedules,
                            alarmStatesResult: .success(reconciledSnapshot),
                            nowMillis: nowMillis,
                            save: { WarmAlarmStore.shared.save($0) }
                        ) {
                        case let .failure(error):
                            self.finishAlarmKitMutation(ids: incompatibleIDs)
                            WarmAlarmPlatformReply.complete(
                                .failure(error), completion: completion, finish: finish
                            )
                        case let .success(work):
                            for alarmId in work.expiredAlarmIDs {
                                if let expiredAlarmKitSchedule = currentSchedules.first(where: {
                                    $0.id == alarmId && $0.alarmKitManaged
                                }) {
                                    self.delegate.handleAlarmKitStop(schedule: expiredAlarmKitSchedule)
                                } else {
                                    WarmAlarmStore.shared.remove(id: alarmId)
                                }
                            }
                            self.finishAlarmKitMutation(ids: incompatibleIDs)
                            self.initializeNotificationState(
                                schedules: work.notificationRecovery,
                                alarmKitManaged: work.alarmKitManaged,
                                nowMillis: nowMillis,
                                completion: completion,
                                finish: finish
                            )
                        }
                    }
                }
            }
        }
    }

    static func resolveAlarmKitInitializationWork(
        schedules: [WarmAlarmScheduleData],
        alarmStatesResult: Result<WarmAlarmAlarmKitSnapshot, Error>,
        nowMillis: Int64,
        save: @escaping (WarmAlarmScheduleData) -> Void = { _ in }
    ) -> Result<WarmAlarmAlarmKitInitializationWork, Error> {
        switch alarmStatesResult {
        case let .failure(error):
            return .failure(error)
        case let .success(snapshot):
            let ownedSchedules = synchronizeAlarmKitOwnership(
                schedules: schedules,
                snapshot: snapshot,
                save: save
            )
            let synchronizedSchedules = synchronizeAlarmKitCountdowns(
                schedules: ownedSchedules,
                snapshot: snapshot,
                save: save
            )
            return .success(selectAlarmKitInitializationWork(
                schedules: synchronizedSchedules,
                scheduledAlarmKitIDs: snapshot.scheduledAlarmIDs,
                nowMillis: nowMillis
            ))
        }
    }

    static func synchronizeAlarmKitOwnership(
        schedules: [WarmAlarmScheduleData],
        snapshot: WarmAlarmAlarmKitSnapshot,
        save: (WarmAlarmScheduleData) -> Void
    ) -> [WarmAlarmScheduleData] {
        schedules.map { schedule in
            let managed = snapshot.scheduledAlarmIDs.contains(WarmAlarmAlarmKitPlan.id(for: schedule.id))
            guard schedule.alarmKitManaged != managed else { return schedule }
            let synchronized = schedule.withAlarmKitManaged(managed)
            save(synchronized)
            return synchronized
        }
    }

    static func incompatibleAlarmKitScheduleIDs(
        schedules: [WarmAlarmScheduleData],
        snapshot: WarmAlarmAlarmKitSnapshot,
        liveActivityConfigured: Bool
    ) -> [UUID] {
        schedules.compactMap { schedule in
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: schedule.id)
            guard snapshot.scheduledAlarmIDs.contains(alarmKitID),
                  !canUseAlarmKit(
                    for: WarmAlarmAlarmKitPlan(schedule: schedule),
                    liveActivityConfigured: liveActivityConfigured
                  )
            else {
                return nil
            }
            return alarmKitID
        }
    }

    static func missingAlarmKitManagedScheduleIDs(
        schedules: [WarmAlarmScheduleData],
        snapshot: WarmAlarmAlarmKitSnapshot
    ) -> [Int64] {
        schedules.compactMap { schedule in
            snapshot.scheduledAlarmIDs.contains(WarmAlarmAlarmKitPlan.id(for: schedule.id))
                ? nil
                : schedule.id
        }
    }

    static func reconcileFallbackPreflightFailure(
        alarmId: Int64,
        previousSchedule: WarmAlarmScheduleData?,
        attemptedAlarmKit: Bool,
        removedPreviousAlarmKit: Bool,
        save: (WarmAlarmScheduleData) -> Void,
        remove: (Int64) -> Void
    ) {
        guard attemptedAlarmKit || removedPreviousAlarmKit else { return }
        if let previousSchedule, !previousSchedule.alarmKitManaged, !removedPreviousAlarmKit {
            save(previousSchedule)
        } else {
            remove(alarmId)
        }
    }

    static func synchronizeAlarmKitCountdowns(
        schedules: [WarmAlarmScheduleData],
        snapshot: WarmAlarmAlarmKitSnapshot,
        save: (WarmAlarmScheduleData) -> Void
    ) -> [WarmAlarmScheduleData] {
        schedules.map { schedule in
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: schedule.id)
            guard snapshot.states[alarmKitID] == .countdown,
                  let nextTriggerDate = snapshot.nextTriggerDates[alarmKitID]
            else {
                return schedule
            }
            let nextTriggerMillis = Int64(nextTriggerDate.timeIntervalSince1970 * 1_000)
            guard schedule.activeSnoozeUntilMillis != nextTriggerMillis else { return schedule }
            let synchronized = schedule.withActiveSnooze(untilMillis: nextTriggerMillis)
            save(synchronized)
            return synchronized
        }
    }

    private func initializeNotificationState(
        schedules: [WarmAlarmScheduleData],
        alarmKitManaged: [WarmAlarmScheduleData],
        nowMillis: Int64,
        completion: @escaping (Result<Void, Error>) -> Void,
        finish: @escaping () -> Void
    ) {
        notificationCenter.getPendingNotificationRequests { [weak self] pending in
            guard let self else {
                finish()
                return
            }
            let alarmKitManagedIdentifiers = Set(alarmKitManaged.flatMap { schedule in
                Self.requestIdentifiers(
                    for: schedule.id,
                    recurrenceWeekdays: schedule.recurrenceWeekdays
                )
            })
            if !alarmKitManagedIdentifiers.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(
                    withIdentifiers: Array(alarmKitManagedIdentifiers)
                )
                self.notificationCenter.removeDeliveredNotifications(
                    withIdentifiers: Array(alarmKitManagedIdentifiers)
                )
            }
            let notificationPending = pending.filter {
                !alarmKitManagedIdentifiers.contains($0.identifier)
            }
            let recurringSchedules = Self.migrateRecurringWallTimes(
                schedules,
                pendingRequests: notificationPending,
                save: { WarmAlarmStore.shared.save($0) }
            )
            let migratedSchedules = Self.migrateOneShotFallbackAnchors(
                recurringSchedules,
                pendingRequests: notificationPending,
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
                pendingRequests: notificationPending,
                nowMillis: nowMillis,
                center: self.notificationCenter
            ) { result in
                WarmAlarmPlatformReply.complete(result, completion: completion, finish: finish)
            }
        }
    }

    static func selectAlarmKitInitializationWork(
        schedules: [WarmAlarmScheduleData],
        scheduledAlarmKitIDs: Set<UUID>,
        nowMillis: Int64
    ) -> WarmAlarmAlarmKitInitializationWork {
        var alarmKitManaged = [WarmAlarmScheduleData]()
        var notificationRecovery = [WarmAlarmScheduleData]()
        var expiredAlarmIDs = [Int64]()
        for schedule in schedules {
            if scheduledAlarmKitIDs.contains(WarmAlarmAlarmKitPlan.id(for: schedule.id)) {
                alarmKitManaged.append(schedule)
            } else if Self.shouldRecover(schedule: schedule, nowMillis: nowMillis)
                || schedule.recurrenceWeekdays?.isEmpty == false {
                notificationRecovery.append(schedule)
            } else {
                expiredAlarmIDs.append(schedule.id)
            }
        }
        return WarmAlarmAlarmKitInitializationWork(
            alarmKitManaged: alarmKitManaged,
            notificationRecovery: notificationRecovery,
            expiredAlarmIDs: expiredAlarmIDs
        )
    }

    private func recoverAlarms(
        _ alarms: [WarmAlarmScheduleData],
        pendingRequests: [UNNotificationRequest],
        nowMillis: Int64,
        center: UNUserNotificationCenter,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let staleIdentifiers = Self.staleRecoveryRequestIdentifiers(
            for: alarms,
            in: pendingRequests
        )
        let pendingIdentifiers = Set(pendingRequests.map(\.identifier)).subtracting(staleIdentifiers)
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIdentifiers))
        }
        let requestGroups = alarms.map { schedule in
            let content = delegate.makeContent(from: schedule)
            return (
                schedule: schedule,
                content: content,
                requests: Self.makeRecoveryRequests(
                    for: schedule,
                    nowMillis: nowMillis,
                    pendingIdentifiers: pendingIdentifiers,
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
            let currentGenerationRequests = matchingRequests.filter {
                notificationContent(schedule, matches: $0.content)
            }
            let metadataDate = occurrenceMetadata(
                for: schedule.id,
                in: currentGenerationRequests
            )?.primaryDate(in: calendar)
            let primaryTriggerDate = currentGenerationRequests.lazy.compactMap { request -> Date? in
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
        let primaryAtMillis = fallbackAnchorMillis
            ?? schedule.activeSnoozeUntilMillis
            ?? schedule.scheduledAtMillis
        let occurrenceToken = schedule.occurrenceSeriesToken
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
        let alarmKitConfigured = Self.schedulingBackend(
            alarmKitAvailable: alarmKitBackend != nil,
            alarmKitUsageDescription: alarmKitUsageDescription,
            authorizationState: .authorized
        ) == .alarmKit
        completion(.success(WarmAlarmCapabilitiesWire(
            exactScheduling: alarmKitConfigured ? .supported : .limited,
            notificationScheduling: .supported,
            backgroundAudioPlayback: .limited,
            fullScreenPresentation: .unsupported,
            wakeCheck: .unsupported,
            liveActivity: alarmKitConfigured && alarmKitLiveActivityEnabled ? .limited : .unsupported
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
        guard reason == .notificationPermissionDenied || reason == .exactAlarmPermissionDenied else {
            completeRemediation(status: .unsupported, completion: completion)
            return
        }

        let settingsURLString: String
        if reason == .notificationPermissionDenied, #available(iOS 16.0, *) {
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
            let alarmKitConfigured = Self.schedulingBackend(
                alarmKitAvailable: self.alarmKitBackend != nil,
                alarmKitUsageDescription: self.alarmKitUsageDescription,
                authorizationState: .authorized
            ) == .alarmKit
            let snapshot = Self.permissionSnapshot(
                notificationsGranted: granted,
                alarmKitConfigured: alarmKitConfigured,
                alarmKitAuthorization: self.alarmKitBackend?.authorizationState
            )
            handler(snapshot.permissionState, snapshot.readiness)
        }
    }

    static func permissionSnapshot(
        notificationsGranted: Bool,
        alarmKitConfigured: Bool,
        alarmKitAuthorization: WarmAlarmAlarmKitAuthorization?
    ) -> WarmAlarmPermissionSnapshot {
        let exactAlarmGranted = alarmKitConfigured && alarmKitAuthorization == .authorized
        let permissionState = WarmAlarmPermissionStateWire(
            notificationsGranted: notificationsGranted,
            exactAlarmGranted: exactAlarmGranted,
            fullScreenIntentGranted: false
        )
        if exactAlarmGranted {
            return WarmAlarmPermissionSnapshot(
                permissionState: permissionState,
                readiness: WarmAlarmReadinessWire(level: .ready, reasons: [])
            )
        }
        if alarmKitConfigured, alarmKitAuthorization == .notDetermined {
            return WarmAlarmPermissionSnapshot(
                permissionState: permissionState,
                readiness: WarmAlarmReadinessWire(level: .limited, reasons: [.unknown])
            )
        }

        var reasons = [WarmAlarmReadinessReasonWire]()
        if !notificationsGranted { reasons.append(.notificationPermissionDenied) }
        if alarmKitConfigured, alarmKitAuthorization == .denied {
            reasons.append(.exactAlarmPermissionDenied)
        }
        reasons.append(.backgroundExecutionLimited)
        return WarmAlarmPermissionSnapshot(
            permissionState: permissionState,
            readiness: WarmAlarmReadinessWire(
                level: notificationsGranted ? .limited : .blocked,
                reasons: reasons
            )
        )
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
        calendar: Calendar = .current,
        occurrenceSeriesToken: String? = nil
    ) -> [UNNotificationRequest] {
        let fireDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1000.0)
        let seriesToken = occurrenceSeriesToken ?? Self.occurrenceSeriesToken(for: schedule.id)
        let occurrenceMetadata = WarmAlarmOccurrenceMetadata(
            token: seriesToken,
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
                token: seriesToken,
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
            token: schedule.occurrenceSeriesToken,
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
        return WarmAlarmRecurrence.nextOccurrenceMillis(
            scheduledAtMillis: schedule.scheduledAtMillis,
            weekdays: weekdays,
            afterMillis: nowMillis,
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

    static func staleRecoveryRequestIdentifiers(
        for schedules: [WarmAlarmScheduleData],
        in requests: [UNNotificationRequest]
    ) -> Set<String> {
        Set(schedules.flatMap { schedule in
            notificationRequests(for: schedule.id, in: requests)
                .filter { !notificationContent(schedule, matches: $0.content) }
                .map(\.identifier)
        })
    }

    static func pendingSnoozeRequests(
        for schedule: WarmAlarmScheduleData,
        in requests: [UNNotificationRequest]
    ) -> [UNNotificationRequest] {
        guard let activeSnoozeUntilMillis = schedule.activeSnoozeUntilMillis else {
            return []
        }
        let identifiers = Set([String(schedule.id)] + fallbackIdentifiers(for: schedule.id))
        return requests.filter { request in
            guard identifiers.contains(request.identifier),
                  notificationContent(schedule, matches: request.content),
                  let metadata = occurrenceMetadata(from: request.content) else {
                return false
            }
            return !metadata.floating && metadata.primaryEpochMillis == activeSnoozeUntilMillis
        }
    }

    static func makeSnoozeRollbackRequests(
        for schedule: WarmAlarmScheduleData,
        restoring requests: [UNNotificationRequest],
        nowMillis: Int64,
        content: UNNotificationContent,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        let restoringIdentifiers = Set(requests.map(\.identifier))
        guard let anchorMillis = schedule.fallbackAnchorMillis else { return [] }
        let metadata = WarmAlarmOccurrenceMetadata(
            token: schedule.occurrenceSeriesToken,
            primaryAtMillis: anchorMillis,
            calendar: calendar,
            floating: false
        )
        var rollbackRequests = [UNNotificationRequest]()
        let primaryIdentifier = String(schedule.id)
        if restoringIdentifiers.contains(primaryIdentifier),
           let activeSnoozeUntilMillis = schedule.activeSnoozeUntilMillis,
           activeSnoozeUntilMillis > nowMillis {
            rollbackRequests.append(UNNotificationRequest(
                identifier: primaryIdentifier,
                content: contentWithOccurrenceMetadata(content, metadata: metadata, ordinal: 0),
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1.0, Double(activeSnoozeUntilMillis - nowMillis) / 1_000.0),
                    repeats: false
                )
            ))
        }
        rollbackRequests += fallbackIdentifiers(for: schedule.id).enumerated().compactMap { index, identifier in
            let fireAtMillis = fallbackFireAtMillis(anchorMillis: anchorMillis, index: index + 1)
            guard restoringIdentifiers.contains(identifier), fireAtMillis > nowMillis else { return nil }
            return UNNotificationRequest(
                identifier: identifier,
                content: contentWithOccurrenceMetadata(content, metadata: metadata, ordinal: index + 1),
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1.0, Double(fireAtMillis - nowMillis) / 1_000.0),
                    repeats: false
                )
            )
        }
        return rollbackRequests
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
                  metadata.hasConsistentPrimaryEpoch(),
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

    private static func occurrenceSeriesToken(for alarmId: Int64) -> String {
        "warm-alarm-v1:\(alarmId)"
    }

    static func newOccurrenceSeriesToken(for alarmId: Int64) -> String {
        "\(occurrenceSeriesToken(for: alarmId)):\(UUID().uuidString)"
    }

    static func notificationContent(
        _ schedule: WarmAlarmScheduleData,
        matches content: UNNotificationContent
    ) -> Bool {
        guard content.userInfo[WarmAlarmOccurrenceMetadata.userInfoKey] != nil else { return true }
        return occurrenceMetadata(from: content)?.token == schedule.occurrenceSeriesToken
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
            let seriesToken = schedule.occurrenceSeriesToken
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
        if let content, !notificationContent(schedule, matches: content) {
            return .max
        }
        if let content,
           let notificationOccurrenceMillis = floatingOneShotOccurrenceMillis(
               for: schedule,
               content: content,
               calendar: calendar
           ) {
            return notificationOccurrenceMillis
        }
        if let content,
           let metadata = occurrenceMetadata(from: content),
           !metadata.floating,
           metadata.token == schedule.occurrenceSeriesToken,
           metadata.primaryEpochMillis == schedule.activeSnoozeUntilMillis,
           metadata.primaryDate(in: calendar) != nil {
            return metadata.primaryEpochMillis
        }
        let recurrenceOccurrenceMillis = latestRecurrenceOccurrenceMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        )
        if let recurrenceOccurrenceMillis,
           let content,
           isFloatingRecurringOccurrence(for: schedule, content: content) {
            return recurrenceOccurrenceMillis
        }
        let fallbackAnchorMillis = recoveryFallbackAnchorMillis(
            for: schedule,
            nowMillis: nowMillis,
            calendar: calendar
        )
        return [fallbackAnchorMillis, recurrenceOccurrenceMillis].compactMap { $0 }.max()
    }

    static func isFloatingRecurringOccurrence(
        for schedule: WarmAlarmScheduleData,
        content: UNNotificationContent
    ) -> Bool {
        guard schedule.recurrenceWeekdays?.isEmpty == false,
              let metadata = occurrenceMetadata(from: content) else {
            return false
        }
        return metadata.floating
            && metadata.token == schedule.occurrenceSeriesToken
            && metadata.hour == schedule.recurrenceHour
            && metadata.minute == schedule.recurrenceMinute
    }

    private static func floatingOneShotOccurrenceMillis(
        for schedule: WarmAlarmScheduleData,
        content: UNNotificationContent,
        calendar: Calendar
    ) -> Int64? {
        guard schedule.recurrenceWeekdays?.isEmpty != false,
              let metadata = occurrenceMetadata(from: content),
              metadata.floating,
              metadata.token == schedule.occurrenceSeriesToken else {
            return nil
        }
        let matchesPersistedOccurrence = metadata.primaryEpochMillis == schedule.oneShotOccurrenceEpochMillis
            || schedule.fallbackAnchorMillis.map { $0 == metadata.primaryEpochMillis } == true
        guard matchesPersistedOccurrence,
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
        let persistedAnchorMillis = schedule.fallbackAnchorMillis
        guard !hasActiveSnoozeFallbacks(for: schedule, nowMillis: nowMillis),
              let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty,
              let hour = schedule.recurrenceHour,
              let minute = schedule.recurrenceMinute else {
            return persistedAnchorMillis
        }
        if schedule.activeSnoozeUntilMillis == nil, let persistedAnchorMillis {
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
        WarmAlarmPlatformReply.performOnMain {
            emitFailure(alarmId, error.localizedDescription)
            WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
        }
    }

    private func scheduleNotificationFallback(
        schedule: WarmAlarmScheduleWire,
        storedSchedule: WarmAlarmScheduleData,
        requests: [UNNotificationRequest],
        staleIdentifiers: [String],
        completion: @escaping (Result<WarmAlarmNotificationSchedulingOutcome, Error>) -> Void
    ) {
        let replacingIdentifiers = Set(staleIdentifiers)
        notificationCenter.getPendingNotificationRequests { [weak self] pendingRequests in
            guard let self else { return }
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
                completion(.failure(Self.pendingLimitError(
                    requiredCoreCount: Self.coreRequestCount(in: requests),
                    availableCount: Self.availableRequestSlotCount(
                        pendingIdentifiers: pendingIdentifiers,
                        replacingIdentifiers: replacingIdentifiers,
                        reservedSlotCount: reservedSlotCount,
                        limit: Self.pendingNotificationLimit
                    )
                )))
                return
            }

            self.delegate.clearHandledForegroundOccurrence(alarmId: schedule.id)
            self.notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
            WarmAlarmStore.shared.save(storedSchedule)
            let capacityWarning = Self.fallbackCapacityWarning(
                omittedCount: selection.omittedFallbackCount
            )
            Self.addRequestsAtomically(
                selection.requests,
                center: self.notificationCenter
            ) { [weak self] error in
                guard let self else { return }
                if let error {
                    WarmAlarmStore.shared.remove(id: schedule.id)
                    self.delegate.emitFailure(alarmId: schedule.id, message: error.localizedDescription)
                    completion(.success(WarmAlarmNotificationSchedulingOutcome(
                        didSchedule: false,
                        warning: WarmAlarmWarningWire(
                            message: "Scheduling failed: \(error.localizedDescription)"
                        )
                    )))
                    return
                }
                completion(.success(WarmAlarmNotificationSchedulingOutcome(
                    didSchedule: true,
                    warning: capacityWarning
                )))
            }
        }
    }

    func prepareSystemSound(
        primaryFilePath: String,
        backgroundAssetPath: String?,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        guard #available(iOS 26.0, *), Self.schedulingBackend(
            alarmKitAvailable: alarmKitBackend != nil,
            alarmKitUsageDescription: alarmKitUsageDescription,
            authorizationState: alarmKitBackend?.authorizationState ?? .denied
        ) == .alarmKit else {
            completion(.success(nil))
            return
        }
        do {
            let background = try backgroundAssetPath.map { asset in
                guard let url = delegate.flutterAssetURL(for: asset) else {
                    throw NSError(domain: "WarmAlarmSoundRenderer", code: 4, userInfo: [
                        NSLocalizedDescriptionKey: "The requested alarm sound asset does not exist."
                    ])
                }
                return url
            }
            let output = try WarmAlarmSoundFiles.prepare(
                primary: URL(fileURLWithPath: primaryFilePath), background: background
            )
            completion(.success(output.path))
        } catch {
            completion(.failure(error))
        }
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
            let occurrenceSeriesToken = Self.newOccurrenceSeriesToken(for: schedule.id)
            let fallbackAnchorMillis = Self.fallbackAnchorMillis(
                for: schedule,
                nowMillis: nowMillis
            )
            let storedSchedule = WarmAlarmScheduleData.from(
                wire: schedule,
                fallbackAnchorMillis: fallbackAnchorMillis,
                occurrenceSeriesToken: occurrenceSeriesToken
            )
            let content = self.delegate.makeContent(from: storedSchedule)
            let requests = Self.makeRequests(
                for: schedule,
                content: content,
                fallbackAnchorMillis: fallbackAnchorMillis,
                occurrenceSeriesToken: occurrenceSeriesToken
            )
            let center = UNUserNotificationCenter.current()
            let previousSchedule = WarmAlarmStore.shared.load(id: schedule.id)
            let staleIdentifiers = Self.requestIdentifiers(
                for: schedule.id,
                recurrenceWeekdays: previousSchedule?.recurrenceWeekdays
            )
            var plan = WarmAlarmAlarmKitPlan(schedule: storedSchedule)
            if previousSchedule?.alarmKitManaged == true {
                self.beginAlarmKitMutation(ids: [plan.id])
            }
            let backendChoice = Self.schedulingBackend(
                alarmKitAvailable: self.alarmKitBackend != nil,
                alarmKitUsageDescription: self.alarmKitUsageDescription,
                authorizationState: self.alarmKitBackend?.authorizationState ?? .denied
            )
            let canUseAlarmKit = Self.canUseAlarmKit(
                for: plan,
                liveActivityConfigured: self.alarmKitLiveActivityEnabled
            )
            let selectedAlarmKitBackend = backendChoice == .alarmKit && canUseAlarmKit
                ? self.alarmKitBackend
                : nil
            if selectedAlarmKitBackend != nil, #available(iOS 26.0, *) {
                do {
                    let source: URL?
                    if let path = storedSchedule.systemSoundFilePath {
                        guard !path.isEmpty else {
                            throw NSError(domain: "WarmAlarmSoundRenderer", code: 4, userInfo: [
                                NSLocalizedDescriptionKey: "The requested system sound path is empty."
                            ])
                        }
                        source = URL(fileURLWithPath: path)
                    } else if let path = plan.soundFilePath, !path.isEmpty {
                        source = URL(fileURLWithPath: path)
                    } else if let asset = plan.soundAssetPath, !asset.isEmpty {
                        guard let url = self.delegate.flutterAssetURL(for: asset) else {
                            throw NSError(domain: "WarmAlarmSoundRenderer", code: 4, userInfo: [
                                NSLocalizedDescriptionKey: "The requested alarm sound asset does not exist."
                            ])
                        }
                        source = url
                    } else {
                        source = nil
                    }
                    if let source {
                        let output: URL
                        if source.standardizedFileURL == WarmAlarmSoundFiles.ownedURL(named: source.lastPathComponent) {
                            let file = try AVAudioFile(forReading: source)
                            guard file.length > 0 else {
                                throw NSError(domain: "WarmAlarmSoundRenderer", code: 1, userInfo: [
                                    NSLocalizedDescriptionKey: "The alarm sound has no readable audio frames."
                                ])
                            }
                            output = source
                        } else {
                            output = try WarmAlarmSoundFiles.prepare(primary: source, background: nil)
                        }
                        plan.preparedSoundName = output.lastPathComponent
                    }
                } catch {
                    self.finishAlarmKitMutation(ids: [plan.id])
                    completion(.failure(error))
                    finish()
                    return
                }
            }
            let configurationWarning = backendChoice == .alarmKit && !canUseAlarmKit
                ? WarmAlarmWarningWire(
                    message: "AlarmKit snooze requires WarmAlarmAlarmKitLiveActivityEnabled; "
                        + "using User Notifications."
                )
                : nil
            var notificationOutcome: WarmAlarmNotificationSchedulingOutcome?

            func route(
                alarmKitBackend: WarmAlarmAlarmKitScheduling?,
                removedPreviousAlarmKit: Bool = false
            ) {
                let attemptedAlarmKit = alarmKitBackend != nil
                WarmAlarmBackendRouting.schedule(
                    plan: plan,
                    alarmKitBackend: alarmKitBackend,
                    fallback: { fallbackCompletion in
                        self.scheduleNotificationFallback(
                            schedule: schedule,
                            storedSchedule: storedSchedule.withAlarmKitManaged(false),
                            requests: requests,
                            staleIdentifiers: staleIdentifiers
                        ) { result in
                            WarmAlarmStore.shared.removeSoundIfUnreferenced(plan.preparedSoundName)
                            if let input = storedSchedule.systemSoundFilePath,
                               URL(fileURLWithPath: input).standardizedFileURL == WarmAlarmSoundFiles.ownedURL(
                                   named: URL(fileURLWithPath: input).lastPathComponent
                               ) {
                                WarmAlarmStore.shared.removeSoundIfUnreferenced(URL(fileURLWithPath: input).lastPathComponent)
                            }
                            switch result {
                            case let .success(outcome):
                                notificationOutcome = outcome
                                fallbackCompletion(nil)
                            case let .failure(error):
                                Self.reconcileFallbackPreflightFailure(
                                    alarmId: schedule.id,
                                    previousSchedule: previousSchedule,
                                    attemptedAlarmKit: attemptedAlarmKit,
                                    removedPreviousAlarmKit: removedPreviousAlarmKit,
                                    save: { WarmAlarmStore.shared.save($0) },
                                    remove: { WarmAlarmStore.shared.remove(id: $0) }
                                )
                                fallbackCompletion(error)
                            }
                        }
                    },
                    completion: { result in
                        switch result {
                        case let .failure(error):
                            self.finishAlarmKitMutation(ids: [plan.id])
                            Self.completePendingLimitFailure(
                                alarmId: schedule.id,
                                error: error,
                                emitFailure: self.delegate.emitFailure,
                                completion: completion,
                                finish: finish
                            )
                        case let .success(outcome):
                            if outcome.backend == .alarmKit {
                                self.delegate.clearHandledForegroundOccurrence(alarmId: schedule.id)
                                center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
                                center.removeDeliveredNotifications(withIdentifiers: staleIdentifiers)
                                WarmAlarmStore.shared.save(
                                    storedSchedule.clearingFallbackAnchor().withAlarmKitManaged(true)
                                        .withAlarmKitSound(named: plan.preparedSoundName)
                                )
                                self.finishAlarmKitSchedule(id: plan.id)
                            } else {
                                self.finishAlarmKitMutation(ids: [plan.id])
                            }
                            if let alarmKitError = outcome.alarmKitError {
                                NSLog(
                                    "[warm_alarm_ios] alarmId=%lld backend=userNotifications fallbackReason=%@",
                                    schedule.id,
                                    alarmKitError.localizedDescription
                                )
                            } else {
                                NSLog(
                                    "[warm_alarm_ios] alarmId=%lld backend=%@",
                                    schedule.id,
                                    outcome.backend == .alarmKit ? "alarmKit" : "userNotifications"
                                )
                            }
                            let didSchedule = outcome.backend == .alarmKit
                                || notificationOutcome?.didSchedule == true
                            if didSchedule {
                                self.delegate.emitScheduled(alarmId: schedule.id)
                            }
                            var warning = configurationWarning
                            if let capacityMessage = notificationOutcome?.warning?.message {
                                warning = WarmAlarmWarningWire(
                                    message: [warning?.message, capacityMessage]
                                        .compactMap { $0 }
                                        .joined(separator: " ")
                                )
                            }
                            if let alarmKitError = outcome.alarmKitError,
                               notificationOutcome?.didSchedule == true {
                                let message = "AlarmKit scheduling failed; using User Notifications: "
                                    + alarmKitError.localizedDescription
                                if let existingMessage = warning?.message {
                                    warning = WarmAlarmWarningWire(message: "\(message) \(existingMessage)")
                                } else {
                                    warning = WarmAlarmWarningWire(message: message)
                                }
                            }
                            self.getReadiness { readinessResult in
                                let readiness = (try? readinessResult.get())
                                    ?? WarmAlarmReadinessWire(
                                        level: .limited,
                                        reasons: [.backgroundExecutionLimited]
                                    )
                                WarmAlarmPlatformReply.complete(.success(WarmAlarmScheduleResultWire(
                                    alarmId: schedule.id,
                                    readiness: readiness,
                                    warning: warning
                                )), completion: completion, finish: finish)
                            }
                        }
                    }
                )
            }

            if previousSchedule?.alarmKitManaged == true,
               selectedAlarmKitBackend == nil,
               let alarmKitBackend = self.alarmKitBackend {
                WarmAlarmNativeCancellation.perform(
                    cancelNative: { nativeCompletion in
                        alarmKitBackend.cancel(id: plan.id, completion: nativeCompletion)
                    },
                    cleanupLocalState: {},
                    completion: { error in
                        if let error {
                            self.finishAlarmKitMutation(ids: [plan.id])
                            Self.completePendingLimitFailure(
                                alarmId: schedule.id,
                                error: error,
                                emitFailure: self.delegate.emitFailure,
                                completion: completion,
                                finish: finish
                            )
                        } else {
                            route(alarmKitBackend: nil, removedPreviousAlarmKit: true)
                        }
                    }
                )
            } else {
                route(alarmKitBackend: selectedAlarmKitBackend)
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
            let storedSchedule = WarmAlarmStore.shared.load(id: id)
            let identifiers = Self.requestIdentifiers(
                for: id,
                recurrenceWeekdays: storedSchedule?.recurrenceWeekdays
            )
            let cleanupLocalState = {
                WarmAlarmStore.shared.remove(id: id)
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
                self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
            guard storedSchedule?.alarmKitManaged == true,
                  let alarmKitBackend = self.alarmKitBackend else {
                cleanupLocalState()
                WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                return
            }
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: id)
            self.beginAlarmKitMutation(ids: [alarmKitID])
            WarmAlarmNativeCancellation.perform(
                cancelNative: { nativeCompletion in
                    alarmKitBackend.cancel(
                        id: alarmKitID,
                        completion: nativeCompletion
                    )
                },
                cleanupLocalState: cleanupLocalState,
                completion: { error in
                    self.finishAlarmKitMutation(ids: [alarmKitID])
                    if let error {
                        WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                    } else {
                        WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                    }
                }
            )
        }
    }

    func cancelAllAlarms(completion: @escaping (Result<Void, Error>) -> Void) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            self.delegate.stopAllIfPlaying()
            let cleanupLocalState = {
                WarmAlarmStore.shared.clear()
                self.notificationCenter.removeAllPendingNotificationRequests()
            }
            let hasAlarmKitManagedSchedule = WarmAlarmStore.shared.loadAll().values.contains {
                $0.alarmKitManaged
            }
            guard hasAlarmKitManagedSchedule, let alarmKitBackend = self.alarmKitBackend else {
                cleanupLocalState()
                WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                return
            }
            let alarmKitIDs = WarmAlarmStore.shared.loadAll().values
                .filter(\.alarmKitManaged)
                .map { WarmAlarmAlarmKitPlan.id(for: $0.id) }
            self.beginAlarmKitMutation(ids: alarmKitIDs)
            WarmAlarmNativeCancellation.perform(
                cancelNative: alarmKitBackend.cancelAll,
                cleanupLocalState: cleanupLocalState,
                completion: { error in
                    self.finishAlarmKitMutation(ids: alarmKitIDs)
                    if let error {
                        WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                    } else {
                        WarmAlarmPlatformReply.complete(.success(()), completion: completion, finish: finish)
                    }
                }
            )
        }
    }

    func getScheduledAlarms(completion: @escaping (Result<[WarmAlarmSnapshotWire], Error>) -> Void) {
        notificationMutationQueue.enqueue { [weak self] finish in
            guard let self else {
                finish()
                return
            }
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
            let hasAlarmKitManagedSchedule = WarmAlarmStore.shared.loadAll().values.contains {
                $0.alarmKitManaged
            }
            guard hasAlarmKitManagedSchedule, let alarmKitBackend = self.alarmKitBackend else {
                WarmAlarmPlatformReply.complete(
                    .success(Self.scheduledAlarmSnapshots(nowMillis: nowMillis)),
                    completion: completion,
                    finish: finish
                )
                return
            }
            alarmKitBackend.snapshot { result in
                switch result {
                case let .failure(error):
                    WarmAlarmPlatformReply.complete(.failure(error), completion: completion, finish: finish)
                case let .success(snapshot):
                    let managedSchedules = WarmAlarmStore.shared.loadAll().values.filter {
                        $0.alarmKitManaged
                    }
                    Self.missingAlarmKitManagedScheduleIDs(
                        schedules: Array(managedSchedules),
                        snapshot: snapshot
                    ).forEach { WarmAlarmStore.shared.remove(id: $0) }
                    _ = Self.synchronizeAlarmKitCountdowns(
                        schedules: managedSchedules.filter {
                            snapshot.scheduledAlarmIDs.contains(WarmAlarmAlarmKitPlan.id(for: $0.id))
                        },
                        snapshot: snapshot,
                        save: { WarmAlarmStore.shared.save($0) }
                    )
                    WarmAlarmPlatformReply.complete(
                        .success(Self.scheduledAlarmSnapshots(nowMillis: nowMillis)),
                        completion: completion,
                        finish: finish
                    )
                }
            }
        }
    }

    private static func scheduledAlarmSnapshots(nowMillis: Int64) -> [WarmAlarmSnapshotWire] {
        WarmAlarmStore.shared.loadAll().map { _, data in
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
                    },
                    systemSoundFilePath: data.systemSoundFilePath
                ),
                recurrence: data.recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) },
                snooze: data.snoozeDurationMillis.map { WarmAlarmSnoozeWire(durationMillis: $0) },
                payload: data.payload,
                systemManagedAudio: data.systemManagedAudio
            )
        }
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
        if alarmId.map({ playingId == $0 }) ?? (playingId != nil) {
            completion(.success(true))
            return
        }
        let managedSchedules = WarmAlarmStore.shared.loadAll().values.filter { $0.alarmKitManaged }
        let shouldReadAlarmKit = if let alarmId {
            managedSchedules.contains { $0.id == alarmId }
        } else {
            !managedSchedules.isEmpty
        }
        guard shouldReadAlarmKit, let alarmKitBackend else {
            completion(.success(false))
            return
        }
        alarmKitBackend.snapshot { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(snapshot):
                completion(.success(snapshot.isRinging(alarmId: alarmId)))
            }
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
