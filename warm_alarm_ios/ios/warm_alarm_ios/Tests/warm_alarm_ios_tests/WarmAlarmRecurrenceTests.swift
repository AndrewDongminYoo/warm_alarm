import XCTest

@testable import warm_alarm_ios

final class WarmAlarmRecurrenceTests: XCTestCase {
    func testIsoToAppleWeekdayMapping() {
        // ISO 1=Mon..7=Sun  ->  Apple 1=Sun..7=Sat
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 1), 2) // Monday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 2), 3) // Tuesday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 3), 4) // Wednesday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 4), 5) // Thursday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 5), 6) // Friday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 6), 7) // Saturday
        XCTAssertEqual(WarmAlarmRecurrence.appleWeekday(fromIso: 7), 1) // Sunday (wraparound)
    }

    func testMissingIdentifiersOnlyReturnsAbsentRecurringRequests() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            activeSnoozeUntilMillis: nil,
            nowMillis: 2_000,
            pendingIdentifiers: ["42#1", "42#5"]
        )

        XCTAssertEqual(missing, ["42#3"])
    }

    func testMissingIdentifiersDoesNotAddOneShotRequestForCompleteRecurrence() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            activeSnoozeUntilMillis: nil,
            nowMillis: 2_000,
            pendingIdentifiers: ["42#1", "42#3", "42#5"]
        )

        XCTAssertTrue(missing.isEmpty)
    }

    func testRecurringScheduleRemainsRecoverableAfterOriginalDate() {
        XCTAssertTrue(WarmAlarmRecurrence.shouldRecover(
            scheduledAtMillis: 1_000,
            weekdays: [1],
            activeSnoozeUntilMillis: nil,
            nowMillis: 2_000
        ))
    }

    func testMissingIdentifiersIncludesActiveSnoozeForRecurringSchedule() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1, 3, 5],
            activeSnoozeUntilMillis: 3_000,
            nowMillis: 2_000,
            pendingIdentifiers: ["42#1", "42#5"]
        )

        XCTAssertEqual(missing, ["42#3", "42"])
    }

    func testRecoveryFireTimeKeepsRecurrenceSeparateFromActiveSnooze() {
        XCTAssertEqual(WarmAlarmRecurrence.recoveryFireAtMillis(
            identifier: "42#3",
            scheduledAtMillis: 1_000,
            activeSnoozeUntilMillis: 3_000,
            nowMillis: 2_000
        ), 1_000)
        XCTAssertEqual(WarmAlarmRecurrence.recoveryFireAtMillis(
            identifier: "42",
            scheduledAtMillis: 1_000,
            activeSnoozeUntilMillis: 3_000,
            nowMillis: 2_000
        ), 3_000)
    }

    func testExpiredActiveSnoozeIsNotRecovered() {
        let missing = WarmAlarmRecurrence.missingIdentifiers(
            alarmId: 42,
            weekdays: [1],
            activeSnoozeUntilMillis: 1_500,
            nowMillis: 2_000,
            pendingIdentifiers: ["42#1"]
        )

        XCTAssertTrue(missing.isEmpty)
    }
}
