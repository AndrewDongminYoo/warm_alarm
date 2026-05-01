import Foundation

struct WarmAlarmScheduleData: Codable {
    let id: Int64
    let scheduledAtMillis: Int64
    let notificationTitle: String
    let notificationBody: String
    let stopActionTitle: String?
    let snoozeActionTitle: String?
    let filePath: String?
    let assetPath: String?
    let loop: Bool
    let volume: Double?
    let vibrate: Bool
    let fadeInDurationMillis: Int64?
    let recurrenceWeekdays: [Int64]?
    let snoozeDurationMillis: Int64?
    let payload: String?
}

extension WarmAlarmScheduleData {
    static func from(wire: WarmAlarmScheduleWire) -> WarmAlarmScheduleData {
        WarmAlarmScheduleData(
            id: wire.id,
            scheduledAtMillis: wire.scheduledAtMillis,
            notificationTitle: wire.notification.title,
            notificationBody: wire.notification.body,
            stopActionTitle: wire.notification.stopActionTitle,
            snoozeActionTitle: wire.notification.snoozeActionTitle,
            filePath: wire.audio.filePath,
            assetPath: wire.audio.assetPath,
            loop: wire.audio.loop,
            volume: wire.audio.volume,
            vibrate: wire.audio.vibrate,
            fadeInDurationMillis: wire.audio.fadeInDurationMillis,
            recurrenceWeekdays: wire.recurrence?.weekdays,
            snoozeDurationMillis: wire.snooze?.durationMillis,
            payload: wire.payload
        )
    }
}

final class WarmAlarmStore: @unchecked Sendable {
    static let shared = WarmAlarmStore()
    private let defaults = UserDefaults.standard
    private let key = "warm_alarm_schedules"
    private init() {}

    func save(_ data: WarmAlarmScheduleData) {
        var all = loadRaw()
        all[String(data.id)] = data
        persist(all)
    }

    func load(id: Int64) -> WarmAlarmScheduleData? {
        loadRaw()[String(id)]
    }

    func remove(id: Int64) {
        var all = loadRaw()
        all.removeValue(forKey: String(id))
        persist(all)
    }

    func loadAll() -> [Int64: WarmAlarmScheduleData] {
        Dictionary(
            uniqueKeysWithValues: loadRaw().compactMap { key, value in
                Int64(key).map { ($0, value) }
            }
        )
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func loadRaw() -> [String: WarmAlarmScheduleData] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: WarmAlarmScheduleData].self, from: data)
        else { return [:] }
        return decoded
    }

    private func persist(_ all: [String: WarmAlarmScheduleData]) {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }
}
