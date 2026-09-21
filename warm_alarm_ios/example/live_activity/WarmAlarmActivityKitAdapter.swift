import ActivityKit
import Foundation
import warm_alarm_ios

/// Call `WarmAlarmLiveActivityRegistration.register()` from the app target at launch.
enum WarmAlarmLiveActivityRegistration {
    static func register() {
        if #available(iOS 16.2, *) {
            WarmAlarmLiveActivityHost.register(adapter: WarmAlarmActivityKitAdapter())
        }
    }
}

@available(iOS 16.2, *)
private final class WarmAlarmActivityKitAdapter: WarmAlarmLiveActivityAdapter {
    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let reply = WarmAlarmLiveActivityReply(completion)
        Task { @MainActor in
            do {
                let activity = try Activity<WarmAlarmActivityAttributes>.request(
                    attributes: WarmAlarmActivityAttributes(alarmId: state.alarmId),
                    content: Self.content(for: state),
                    pushType: nil
                )
                reply(.success(activity.id))
            } catch {
                reply(.failure(error))
            }
        }
    }

    func update(
        activityId: String,
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let reply = WarmAlarmLiveActivityReply(completion)
        Task { @MainActor in
            guard let activity = Activity<WarmAlarmActivityAttributes>.activities.first(where: {
                $0.id == activityId
            }) else {
                reply(.success(false))
                return
            }
            guard activity.attributes.alarmId == state.alarmId else {
                reply(.failure(WarmAlarmActivityKitAdapterError.alarmIdentityMismatch))
                return
            }
            await activity.update(Self.content(for: state))
            reply(.success(true))
        }
    }

    func end(
        activityId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let reply = WarmAlarmLiveActivityReply(completion)
        Task { @MainActor in
            guard let activity = Activity<WarmAlarmActivityAttributes>.activities.first(where: {
                $0.id == activityId
            }) else {
                reply(.success(false))
                return
            }
            await activity.end(nil, dismissalPolicy: .default)
            reply(.success(true))
        }
    }

    private static func content(
        for state: WarmAlarmLiveActivityState
    ) -> ActivityContent<WarmAlarmActivityAttributes.ContentState> {
        ActivityContent(
            state: WarmAlarmActivityAttributes.ContentState(
                title: state.title,
                status: state.status.sampleStatus,
                scheduledAt: state.scheduledAt
            ),
            staleDate: state.scheduledAt
        )
    }
}

private enum WarmAlarmActivityKitAdapterError: LocalizedError {
    case alarmIdentityMismatch

    var errorDescription: String? {
        "The Live Activity does not belong to the requested alarm."
    }
}

private final class WarmAlarmLiveActivityReply<Value>: @unchecked Sendable {
    private let completion: (Result<Value, Error>) -> Void

    init(_ completion: @escaping (Result<Value, Error>) -> Void) {
        self.completion = completion
    }

    func callAsFunction(_ result: Result<Value, Error>) {
        completion(result)
    }
}

private extension WarmAlarmLiveActivityDisplayStatus {
    var sampleStatus: WarmAlarmActivityAttributes.Status {
        switch self {
        case .scheduled: .scheduled
        case .ringing: .ringing
        case .snoozed: .snoozed
        }
    }
}
