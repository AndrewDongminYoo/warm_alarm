import XCTest

@testable import warm_alarm_macos

final class WarmAlarmRecurrenceTests: XCTestCase {
    func testMissingIdentifiersOnlyReturnsAbsentRecurringRequests() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            pendingIdentifiers: ["42#1", "42#5"]
        )

        XCTAssertEqual(missing, ["42#3"])
    }

    func testMissingIdentifiersDoesNotAddOneShotRequestForCompleteRecurrence() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            pendingIdentifiers: ["42#1", "42#3", "42#5"]
        )

        XCTAssertTrue(missing.isEmpty)
    }

    func testRecurringScheduleRemainsRecoverableAfterOriginalDate() {
        XCTAssertTrue(WarmAlarmRecurrence.shouldRecover(
            scheduledAtMillis: 1_000,
            weekdays: [1],
            nowMillis: 2_000
        ))
    }
}
