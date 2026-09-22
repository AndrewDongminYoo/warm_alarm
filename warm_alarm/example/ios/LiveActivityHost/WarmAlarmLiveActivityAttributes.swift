import ActivityKit
import Foundation

/// Add this file to both the iOS app target and the Widget Extension target.
struct WarmAlarmActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let title: String
        let status: Status
        let scheduledAt: Date?
    }

    enum Status: String, Codable, Hashable, Sendable {
        case scheduled
        case ringing
        case snoozed
    }

    let alarmId: Int64
}
