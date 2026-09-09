import Foundation

#if canImport(AlarmKit)
import ActivityKit
@preconcurrency import AlarmKit
import SwiftUI

@available(iOS 26.0, *)
public typealias WarmAlarmAlarmKitMetadata = Never

@available(iOS 26.0, *)
extension Never: @retroactive AlarmMetadata {}

@available(iOS 26.0, *)
final class WarmAlarmSystemAlarmKitBackend: WarmAlarmAlarmKitScheduling, @unchecked Sendable {
    private final class Reply: @unchecked Sendable {
        private let completion: (Error?) -> Void

        init(_ completion: @escaping (Error?) -> Void) {
            self.completion = completion
        }

        func callAsFunction(_ error: Error?) {
            completion(error)
        }
    }

    private final class SnapshotReply: @unchecked Sendable {
        private let completion: (Result<WarmAlarmAlarmKitSnapshot, Error>) -> Void

        init(_ completion: @escaping (Result<WarmAlarmAlarmKitSnapshot, Error>) -> Void) {
            self.completion = completion
        }

        func callAsFunction(_ result: Result<WarmAlarmAlarmKitSnapshot, Error>) {
            completion(result)
        }
    }

    private final class ObservationReply: @unchecked Sendable {
        private let observer: (WarmAlarmAlarmKitSnapshot) -> Void

        init(_ observer: @escaping (WarmAlarmAlarmKitSnapshot) -> Void) {
            self.observer = observer
        }

        func callAsFunction(_ snapshot: WarmAlarmAlarmKitSnapshot) {
            observer(snapshot)
        }
    }

    private let manager = AlarmManager.shared
    private var observationTask: Task<Void, Never>?

    var authorizationState: WarmAlarmAlarmKitAuthorization {
        switch manager.authorizationState {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    func schedule(_ plan: WarmAlarmAlarmKitPlan, completion: @escaping (Error?) -> Void) {
        let reply = Reply(completion)
        Task { @MainActor [manager] in
            do {
                let configuration = Self.configuration(for: plan)
                _ = try await manager.schedule(id: plan.id, configuration: configuration)
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    func cancel(id: UUID, completion: @escaping (Error?) -> Void) {
        let reply = Reply(completion)
        Task { @MainActor [manager] in
            do {
                if let alarm = try manager.alarms.first(where: { $0.id == id }) {
                    try Self.cancel(alarm, manager: manager)
                }
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    func cancelAll(completion: @escaping (Error?) -> Void) {
        let reply = Reply(completion)
        Task { @MainActor [manager] in
            do {
                for alarm in try manager.alarms where WarmAlarmAlarmKitPlan.owns(alarm.id) {
                    try Self.cancel(alarm, manager: manager)
                }
                reply(nil)
            } catch {
                reply(error)
            }
        }
    }

    func snapshot(completion: @escaping (Result<WarmAlarmAlarmKitSnapshot, Error>) -> Void) {
        let reply = SnapshotReply(completion)
        Task { @MainActor [manager] in
            do {
                reply(.success(Self.makeSnapshot(alarms: try manager.alarms)))
            } catch {
                reply(.failure(error))
            }
        }
    }

    func observe(_ observer: @escaping (WarmAlarmAlarmKitSnapshot) -> Void) {
        observationTask?.cancel()
        let reply = ObservationReply(observer)
        observationTask = Task { @MainActor [manager] in
            for await alarms in manager.alarmUpdates {
                guard !Task.isCancelled else { return }
                reply(Self.makeSnapshot(alarms: alarms))
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    @MainActor
    private static func cancel(_ alarm: Alarm, manager: AlarmManager) throws {
        switch WarmAlarmAlarmKitCancellationAction.forState(alarm.state.warmAlarmState) {
        case .cancel:
            try manager.cancel(id: alarm.id)
        case .stopThenCancel:
            try manager.stop(id: alarm.id)
            if try manager.alarms.contains(where: { $0.id == alarm.id }) {
                try manager.cancel(id: alarm.id)
            }
        }
    }

    @MainActor
    private static func makeSnapshot(alarms: [Alarm]) -> WarmAlarmAlarmKitSnapshot {
        var states = [UUID: WarmAlarmAlarmKitState]()
        for alarm in alarms where WarmAlarmAlarmKitPlan.owns(alarm.id) {
            states[alarm.id] = alarm.state.warmAlarmState
        }
        var nextTriggerDates = [UUID: Date]()
        for activity in Activity<AlarmAttributes<WarmAlarmAlarmKitMetadata>>.activities {
            let presentationState = activity.content.state
            guard states[presentationState.alarmID] == .countdown else { continue }
            if case let .countdown(countdown) = presentationState.mode {
                nextTriggerDates[presentationState.alarmID] = countdown.fireDate
            }
        }
        return WarmAlarmAlarmKitSnapshot(states: states, nextTriggerDates: nextTriggerDates)
    }

    private static func configuration(
        for plan: WarmAlarmAlarmKitPlan
    ) -> AlarmManager.AlarmConfiguration<WarmAlarmAlarmKitMetadata> {
        let title = LocalizedStringResource(stringLiteral: plan.title)
        let secondaryButton = plan.snoozeTitle.map {
            AlarmButton(
                text: LocalizedStringResource(stringLiteral: $0),
                textColor: .white,
                systemImageName: "zzz"
            )
        }
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButton == nil ? nil : .countdown
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: LocalizedStringResource(stringLiteral: plan.stopTitle),
                    textColor: .white,
                    systemImageName: "stop.circle"
                ),
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButton == nil ? nil : .countdown
            )
        }

        let countdown: AlarmPresentation.Countdown?
        let paused: AlarmPresentation.Paused?
        if plan.snoozeDuration == nil {
            countdown = nil
            paused = nil
        } else {
            countdown = AlarmPresentation.Countdown(
                title: title,
                pauseButton: AlarmButton(
                    text: "Pause",
                    textColor: .white,
                    systemImageName: "pause.fill"
                )
            )
            paused = AlarmPresentation.Paused(
                title: title,
                resumeButton: AlarmButton(
                    text: "Resume",
                    textColor: .white,
                    systemImageName: "play.fill"
                )
            )
        }

        let attributes = AlarmAttributes<WarmAlarmAlarmKitMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: nil,
            tintColor: .orange
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: plan.snoozeDuration.map {
                Alarm.CountdownDuration(preAlert: nil, postAlert: $0)
            },
            schedule: plan.alarmKitSchedule,
            attributes: attributes,
            sound: plan.preparedSoundName.map { .named($0) } ?? .default
        )
    }
}

@available(iOS 26.0, *)
private extension Alarm.State {
    var warmAlarmState: WarmAlarmAlarmKitState {
        switch self {
        case .scheduled: .scheduled
        case .countdown: .countdown
        case .paused: .paused
        case .alerting: .alerting
        @unknown default: .scheduled
        }
    }
}

@available(iOS 26.0, *)
private extension WarmAlarmAlarmKitPlan {
    var alarmKitSchedule: Alarm.Schedule {
        switch schedule {
        case let .fixed(date):
            return .fixed(date)
        case let .weekly(hour, minute, weekdays):
            return .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
                repeats: .weekly(weekdays.map(\.alarmKitWeekday))
            ))
        }
    }
}

@available(iOS 26.0, *)
private extension WarmAlarmAlarmKitWeekday {
    var alarmKitWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }
}
#endif

enum WarmAlarmAlarmKitBackendFactory {
    static func make() -> WarmAlarmAlarmKitScheduling? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return WarmAlarmSystemAlarmKitBackend()
        }
        #endif
        return nil
    }
}
