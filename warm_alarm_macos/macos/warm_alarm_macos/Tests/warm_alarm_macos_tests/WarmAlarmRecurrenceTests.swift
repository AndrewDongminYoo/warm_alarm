import XCTest

@testable import warm_alarm_macos

final class WarmAlarmRecurrenceTests: XCTestCase {
    func testRestartRecoveryUsesEveryWeekdayIdentifierWhenOneShotIsPending() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            activeSnoozeUntilMillis: nil,
            nowMillis: 2_000,
            pendingIdentifiers: ["42"]
        )

        XCTAssertEqual(missing, ["42#1", "42#3", "42#5"])
    }
}
