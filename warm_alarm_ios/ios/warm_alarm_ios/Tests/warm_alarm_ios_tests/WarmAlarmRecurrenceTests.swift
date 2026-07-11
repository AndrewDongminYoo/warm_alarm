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
}
