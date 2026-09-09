import Foundation

enum WarmAlarmAlarmKitAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

enum WarmAlarmAlarmKitState: Equatable, Sendable {
    case scheduled
    case countdown
    case paused
    case alerting
}

enum WarmAlarmAlarmKitCancellationAction: Equatable, Sendable {
    case cancel
    case stopThenCancel

    static func forState(_ state: WarmAlarmAlarmKitState) -> Self {
        state == .alerting ? .stopThenCancel : .cancel
    }
}

struct WarmAlarmAlarmKitSnapshot: Equatable, Sendable {
    let states: [UUID: WarmAlarmAlarmKitState]
    let nextTriggerDates: [UUID: Date]

    init(
        states: [UUID: WarmAlarmAlarmKitState],
        nextTriggerDates: [UUID: Date] = [:]
    ) {
        self.states = states
        self.nextTriggerDates = nextTriggerDates
    }

    var scheduledAlarmIDs: Set<UUID> {
        Set(states.keys)
    }

    func isRinging(alarmId: Int64?) -> Bool {
        if let alarmId {
            return states[WarmAlarmAlarmKitPlan.id(for: alarmId)] == .alerting
        }
        return states.values.contains(.alerting)
    }

    func removing(ids: Set<UUID>) -> WarmAlarmAlarmKitSnapshot {
        WarmAlarmAlarmKitSnapshot(
            states: states.filter { !ids.contains($0.key) },
            nextTriggerDates: nextTriggerDates.filter { !ids.contains($0.key) }
        )
    }
}

enum WarmAlarmAlarmKitWeekday: Equatable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    init?(isoWeekday: Int64) {
        switch isoWeekday {
        case 1: self = .monday
        case 2: self = .tuesday
        case 3: self = .wednesday
        case 4: self = .thursday
        case 5: self = .friday
        case 6: self = .saturday
        case 7: self = .sunday
        default: return nil
        }
    }
}

enum WarmAlarmAlarmKitSchedule: Equatable, Sendable {
    case fixed(Date)
    case weekly(hour: Int, minute: Int, weekdays: [WarmAlarmAlarmKitWeekday])
}

struct WarmAlarmAlarmKitPlan: Equatable, Sendable {
    let id: UUID
    let schedule: WarmAlarmAlarmKitSchedule
    let snoozeDuration: TimeInterval?
    let title: String
    let stopTitle: String
    let snoozeTitle: String?
    let soundFilePath: String?
    let soundAssetPath: String?
    var preparedSoundName: String?

    init(schedule: WarmAlarmScheduleData, calendar: Calendar = .current) {
        id = Self.id(for: schedule.id)
        if let weekdays = schedule.recurrenceWeekdays, !weekdays.isEmpty {
            let date = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1_000)
            let components = calendar.dateComponents([.hour, .minute], from: date)
            self.schedule = .weekly(
                hour: schedule.recurrenceHour ?? components.hour ?? 0,
                minute: schedule.recurrenceMinute ?? components.minute ?? 0,
                weekdays: weekdays.compactMap(WarmAlarmAlarmKitWeekday.init)
            )
        } else {
            self.schedule = .fixed(Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1_000))
        }
        snoozeDuration = schedule.snoozeDurationMillis.map { TimeInterval($0) / 1_000 }
        title = schedule.notificationTitle
        stopTitle = schedule.stopActionTitle ?? "Stop"
        snoozeTitle = schedule.snoozeDurationMillis == nil ? nil : schedule.snoozeActionTitle ?? "Snooze"
        soundFilePath = schedule.filePath
        soundAssetPath = schedule.assetPath
    }

    static func id(for alarmId: Int64) -> UUID {
        let value = UInt64(bitPattern: alarmId).bigEndian
        let suffix = withUnsafeBytes(of: value) { Array($0) }
        return UUID(uuid: (
            0x57, 0x41, 0x52, 0x4D,
            0x41, 0x4C, 0x41, 0x52,
            suffix[0], suffix[1], suffix[2], suffix[3],
            suffix[4], suffix[5], suffix[6], suffix[7]
        ))
    }

    static func owns(_ id: UUID) -> Bool {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.starts(with: [0x57, 0x41, 0x52, 0x4D, 0x41, 0x4C, 0x41, 0x52])
        }
    }
}

protocol WarmAlarmAlarmKitScheduling: AnyObject {
    var authorizationState: WarmAlarmAlarmKitAuthorization { get }

    func schedule(_ plan: WarmAlarmAlarmKitPlan, completion: @escaping (Error?) -> Void)
    func cancel(id: UUID, completion: @escaping (Error?) -> Void)
    func cancelAll(completion: @escaping (Error?) -> Void)
    func snapshot(completion: @escaping (Result<WarmAlarmAlarmKitSnapshot, Error>) -> Void)
    func observe(_ observer: @escaping (WarmAlarmAlarmKitSnapshot) -> Void)
    func stopObserving()
}

extension WarmAlarmAlarmKitScheduling {
    func observe(_ observer: @escaping (WarmAlarmAlarmKitSnapshot) -> Void) {}
    func stopObserving() {}
}

enum WarmAlarmNativeCancellation {
    static func perform(
        cancelNative: (@escaping (Error?) -> Void) -> Void,
        cleanupLocalState: @escaping () -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        cancelNative { error in
            guard error == nil else {
                completion(error)
                return
            }
            cleanupLocalState()
            completion(nil)
        }
    }
}

struct WarmAlarmBackendRoutingOutcome {
    let backend: WarmAlarmAppleSchedulingBackend
    let alarmKitError: Error?
}

enum WarmAlarmBackendRouting {
    static func schedule(
        plan: WarmAlarmAlarmKitPlan,
        alarmKitBackend: WarmAlarmAlarmKitScheduling?,
        fallback: @escaping (@escaping (Error?) -> Void) -> Void,
        completion: @escaping (Result<WarmAlarmBackendRoutingOutcome, Error>) -> Void
    ) {
        guard let alarmKitBackend else {
            fallback { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(WarmAlarmBackendRoutingOutcome(
                        backend: .userNotifications,
                        alarmKitError: nil
                    )))
                }
            }
            return
        }

        alarmKitBackend.schedule(plan) { alarmKitError in
            guard let alarmKitError else {
                completion(.success(WarmAlarmBackendRoutingOutcome(
                    backend: .alarmKit,
                    alarmKitError: nil
                )))
                return
            }
            alarmKitBackend.cancel(id: plan.id) { cancellationError in
                if let cancellationError {
                    completion(.failure(cancellationError))
                    return
                }
                fallback { fallbackError in
                    if let fallbackError {
                        completion(.failure(fallbackError))
                    } else {
                        completion(.success(WarmAlarmBackendRoutingOutcome(
                            backend: .userNotifications,
                            alarmKitError: alarmKitError
                        )))
                    }
                }
            }
        }
    }
}
