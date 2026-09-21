import Foundation

extension WarmAlarmPlugin {
    func startLiveActivity(
        state: WarmAlarmLiveActivityStateWire,
        completion: @escaping (Result<WarmAlarmLiveActivityResultWire, Error>) -> Void
    ) {
        WarmAlarmLiveActivityController().start(state: Self.liveActivityState(state)) { result in
            Self.completeLiveActivity(result, completion: completion)
        }
    }

    func updateLiveActivity(
        activityId: String,
        state: WarmAlarmLiveActivityStateWire,
        completion: @escaping (Result<WarmAlarmLiveActivityResultWire, Error>) -> Void
    ) {
        WarmAlarmLiveActivityController().update(activityId: activityId, state: Self.liveActivityState(state)) { result in
            Self.completeLiveActivity(result, completion: completion)
        }
    }

    func endLiveActivity(
        activityId: String,
        completion: @escaping (Result<WarmAlarmLiveActivityResultWire, Error>) -> Void
    ) {
        WarmAlarmLiveActivityController().end(activityId: activityId) { result in
            Self.completeLiveActivity(result, completion: completion)
        }
    }

    private static func liveActivityState(_ state: WarmAlarmLiveActivityStateWire) -> WarmAlarmLiveActivityState {
        let status: WarmAlarmLiveActivityDisplayStatus = switch state.status {
        case .scheduled: .scheduled
        case .ringing: .ringing
        case .snoozed: .snoozed
        }
        return WarmAlarmLiveActivityState(
            alarmId: state.alarmId,
            title: state.title,
            status: status,
            scheduledAt: state.scheduledAtMillis.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        )
    }

    private static func completeLiveActivity(
        _ result: Result<WarmAlarmLiveActivityOperationResult, Error>,
        completion: @escaping (Result<WarmAlarmLiveActivityResultWire, Error>) -> Void
    ) {
        let wireResult = result.map { value in
            let status: WarmAlarmLiveActivityResultStatusWire = switch value.status {
            case .completed: .completed
            case .unsupported: .unsupported
            case .disabled: .disabled
            case .notFound: .notFound
            }
            return WarmAlarmLiveActivityResultWire(status: status, activityId: value.activityId)
        }
        WarmAlarmPlatformReply.complete(wireResult, completion: completion, finish: {})
    }
}
