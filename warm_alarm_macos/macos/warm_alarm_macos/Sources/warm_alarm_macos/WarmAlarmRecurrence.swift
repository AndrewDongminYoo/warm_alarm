import Foundation

/// Weekday-recurrence helpers.
///
/// The public `WarmAlarmRecurrence.weekdays` field uses the ISO 8601 convention
/// (1 = Monday … 7 = Sunday), matching Dart's `DateTime.weekday`. Apple's
/// `Calendar`/`DateComponents.weekday` uses 1 = Sunday … 7 = Saturday, so the two
/// must be mapped explicitly.
enum WarmAlarmRecurrence {
    /// Maps an ISO weekday (1 = Mon … 7 = Sun) to Apple's Calendar weekday
    /// (1 = Sun … 7 = Sat).
    ///
    /// Mon(1) → 2, … Sat(6) → 7, Sun(7) → 1.
    static func appleWeekday(fromIso iso: Int64) -> Int {
        Int((iso % 7) + 1)
    }

    static func missingIdentifiers(
        alarmId: Int64,
        weekdays: [Int64]?,
        activeSnoozeUntilMillis: Int64?,
        nowMillis: Int64,
        pendingIdentifiers: Set<String>
    ) -> [String] {
        var expected = weekdays.flatMap { $0.isEmpty ? nil : $0.map { "\(alarmId)#\($0)" } }
            ?? [String(alarmId)]
        if weekdays?.isEmpty == false,
           let activeSnoozeUntilMillis,
           activeSnoozeUntilMillis > nowMillis {
            expected.append(String(alarmId))
        }
        return expected.filter { !pendingIdentifiers.contains($0) }
    }

    static func shouldRecover(
        scheduledAtMillis: Int64,
        weekdays: [Int64]?,
        activeSnoozeUntilMillis: Int64?,
        nowMillis: Int64
    ) -> Bool {
        weekdays?.isEmpty == false
            || activeSnoozeUntilMillis.map { $0 > nowMillis } == true
            || scheduledAtMillis > nowMillis
    }

    static func nextOccurrenceMillis(
        scheduledAtMillis: Int64,
        weekdays: [Int64],
        afterMillis: Int64,
        calendar: Calendar = .current
    ) -> Int64? {
        guard !weekdays.isEmpty else { return nil }
        let scheduledDate = Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1_000)
        let afterDate = Date(timeIntervalSince1970: Double(afterMillis) / 1_000)
        let time = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        return weekdays.compactMap { isoWeekday -> Date? in
            var components = DateComponents()
            components.weekday = appleWeekday(fromIso: isoWeekday)
            components.hour = time.hour
            components.minute = time.minute
            return calendar.nextDate(after: afterDate, matching: components, matchingPolicy: .nextTime)
        }.min().map { Int64($0.timeIntervalSince1970 * 1_000) }
    }

    static func recoveryFireAtMillis(
        identifier: String,
        scheduledAtMillis: Int64,
        activeSnoozeUntilMillis: Int64?,
        nowMillis: Int64
    ) -> Int64 {
        if !identifier.contains("#"),
           let activeSnoozeUntilMillis,
           activeSnoozeUntilMillis > nowMillis {
            return activeSnoozeUntilMillis
        }
        return scheduledAtMillis
    }
}
