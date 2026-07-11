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
}
