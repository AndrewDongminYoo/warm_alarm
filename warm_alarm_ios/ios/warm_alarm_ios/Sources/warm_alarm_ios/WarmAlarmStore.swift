import Foundation

struct FadeStep: Codable {
    let timeMillis: Int64
    let volume: Double
}

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
    let recurrenceHour: Int?
    let recurrenceMinute: Int?
    let snoozeDurationMillis: Int64?
    let payload: String?
    let volumeEnforced: Bool?
    let fadeSteps: [FadeStep]?
    let keepNotificationAfterAlarmEnds: Bool?
    let activeSnoozeUntilMillis: Int64?
    let fallbackAnchorMillis: Int64?

    // Explicit CodingKeys lets the synthesized encode(to:) work while we
    // override init(from:) in the extension below to add migration defaults.
    private enum CodingKeys: String, CodingKey {
        case id, scheduledAtMillis, notificationTitle, notificationBody
        case stopActionTitle, snoozeActionTitle, filePath, assetPath
        case loop, volume, vibrate, fadeInDurationMillis
        case recurrenceWeekdays, recurrenceHour, recurrenceMinute, snoozeDurationMillis, payload
        case volumeEnforced, fadeSteps, keepNotificationAfterAlarmEnds, activeSnoozeUntilMillis
        case fallbackAnchorMillis
    }
}

extension WarmAlarmScheduleData {
    func snapshotScheduledAtMillis(
        nowMillis: Int64,
        calendar: Calendar = .current
    ) -> Int64 {
        let nextRecurrence = recurrenceWeekdays.flatMap { weekdays in
            if let recurrenceHour, let recurrenceMinute {
                return WarmAlarmRecurrence.nextOccurrenceMillis(
                    hour: recurrenceHour,
                    minute: recurrenceMinute,
                    weekdays: weekdays,
                    afterMillis: nowMillis,
                    calendar: calendar
                )
            }
            return WarmAlarmRecurrence.nextOccurrenceMillis(
                scheduledAtMillis: scheduledAtMillis,
                weekdays: weekdays,
                afterMillis: nowMillis,
                calendar: calendar
            )
        }
        if let activeSnoozeUntilMillis, activeSnoozeUntilMillis > nowMillis {
            return min(activeSnoozeUntilMillis, nextRecurrence ?? activeSnoozeUntilMillis)
        }
        return nextRecurrence ?? scheduledAtMillis
    }

    // Custom decoder provides defaults for fields absent in pre-Phase-3 payloads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        scheduledAtMillis = try c.decode(Int64.self, forKey: .scheduledAtMillis)
        notificationTitle = try c.decode(String.self, forKey: .notificationTitle)
        notificationBody = try c.decode(String.self, forKey: .notificationBody)
        stopActionTitle = try c.decodeIfPresent(String.self, forKey: .stopActionTitle)
        snoozeActionTitle = try c.decodeIfPresent(String.self, forKey: .snoozeActionTitle)
        filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
        assetPath = try c.decodeIfPresent(String.self, forKey: .assetPath)
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? true
        volume = try c.decodeIfPresent(Double.self, forKey: .volume)
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? false
        fadeInDurationMillis = try c.decodeIfPresent(Int64.self, forKey: .fadeInDurationMillis)
        recurrenceWeekdays = try c.decodeIfPresent([Int64].self, forKey: .recurrenceWeekdays)
        recurrenceHour = try c.decodeIfPresent(Int.self, forKey: .recurrenceHour)
        recurrenceMinute = try c.decodeIfPresent(Int.self, forKey: .recurrenceMinute)
        snoozeDurationMillis = try c.decodeIfPresent(Int64.self, forKey: .snoozeDurationMillis)
        payload = try c.decodeIfPresent(String.self, forKey: .payload)
        volumeEnforced = try c.decodeIfPresent(Bool.self, forKey: .volumeEnforced)
        fadeSteps = try c.decodeIfPresent([FadeStep].self, forKey: .fadeSteps)
        keepNotificationAfterAlarmEnds = try c.decodeIfPresent(
            Bool.self, forKey: .keepNotificationAfterAlarmEnds)
        activeSnoozeUntilMillis = try c.decodeIfPresent(Int64.self, forKey: .activeSnoozeUntilMillis)
        fallbackAnchorMillis = try c.decodeIfPresent(Int64.self, forKey: .fallbackAnchorMillis)
    }

    static func from(
        wire: WarmAlarmScheduleWire,
        fallbackAnchorMillis: Int64? = nil,
        calendar: Calendar = .current
    ) -> WarmAlarmScheduleData {
        let recurrenceTime = if wire.recurrence?.weekdays.isEmpty == false {
            calendar.dateComponents(
                [.hour, .minute],
                from: Date(timeIntervalSince1970: Double(wire.scheduledAtMillis) / 1_000)
            )
        } else {
            DateComponents()
        }
        return WarmAlarmScheduleData(
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
            recurrenceHour: recurrenceTime.hour,
            recurrenceMinute: recurrenceTime.minute,
            snoozeDurationMillis: wire.snooze?.durationMillis,
            payload: wire.payload,
            volumeEnforced: wire.audio.volumeEnforced,
            fadeSteps: wire.audio.fadeSteps?.map { FadeStep(timeMillis: $0.timeMillis, volume: $0.volume) },
            keepNotificationAfterAlarmEnds: wire.notification.keepNotificationAfterAlarmEnds,
            activeSnoozeUntilMillis: nil,
            fallbackAnchorMillis: fallbackAnchorMillis
        )
    }

    func withActiveSnooze(
        untilMillis: Int64,
        fallbackAnchorMillis: Int64? = nil
    ) -> WarmAlarmScheduleData {
        copying(
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            activeSnoozeUntilMillis: untilMillis,
            fallbackAnchorMillis: fallbackAnchorMillis
        )
    }

    func withRecurrenceTime(hour: Int, minute: Int) -> WarmAlarmScheduleData {
        copying(
            recurrenceHour: hour,
            recurrenceMinute: minute,
            activeSnoozeUntilMillis: activeSnoozeUntilMillis,
            fallbackAnchorMillis: fallbackAnchorMillis
        )
    }

    func withOneShotAnchor(_ anchorMillis: Int64) -> WarmAlarmScheduleData {
        copying(
            scheduledAtMillis: anchorMillis,
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            activeSnoozeUntilMillis: activeSnoozeUntilMillis,
            fallbackAnchorMillis: anchorMillis
        )
    }

    func clearingFallbackAnchor() -> WarmAlarmScheduleData {
        copying(
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            activeSnoozeUntilMillis: activeSnoozeUntilMillis,
            fallbackAnchorMillis: nil
        )
    }

    private func copying(
        scheduledAtMillis: Int64? = nil,
        recurrenceHour: Int?,
        recurrenceMinute: Int?,
        activeSnoozeUntilMillis: Int64?,
        fallbackAnchorMillis: Int64?
    ) -> WarmAlarmScheduleData {
        WarmAlarmScheduleData(
            id: id, scheduledAtMillis: scheduledAtMillis ?? self.scheduledAtMillis,
            notificationTitle: notificationTitle, notificationBody: notificationBody,
            stopActionTitle: stopActionTitle, snoozeActionTitle: snoozeActionTitle,
            filePath: filePath, assetPath: assetPath,
            loop: loop, volume: volume, vibrate: vibrate,
            fadeInDurationMillis: fadeInDurationMillis,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceHour: recurrenceHour, recurrenceMinute: recurrenceMinute,
            snoozeDurationMillis: snoozeDurationMillis,
            payload: payload,
            volumeEnforced: volumeEnforced,
            fadeSteps: fadeSteps,
            keepNotificationAfterAlarmEnds: keepNotificationAfterAlarmEnds,
            activeSnoozeUntilMillis: activeSnoozeUntilMillis,
            fallbackAnchorMillis: fallbackAnchorMillis
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
