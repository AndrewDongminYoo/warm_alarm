import XCTest
import UserNotifications

@testable import warm_alarm_ios

final class WarmAlarmRequestRegistrationTests: XCTestCase {
    func testAddsEveryRecurringIdentifierBeforeCompleting() {
        let completed = expectation(description: "registration completes")
        var added = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                completion(nil)
            },
            rollback: { _ in
                XCTFail("Successful registration must not roll back requests")
            },
            completion: { error in
                XCTAssertNil(error)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(added, ["42#1", "42#3"])
    }

    func testRollsBackEveryRecurringIdentifierWhenFirstRequestFails() {
        let completed = expectation(description: "registration fails")
        let expectedError = NSError(domain: "WarmAlarmTests", code: 1)
        var rolledBack = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { _, completion in
                completion(expectedError)
            },
            rollback: { identifiers in
                rolledBack = identifiers
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(rolledBack, ["42#1", "42#3"])
    }

    func testRollsBackEveryRecurringIdentifierWhenLaterRequestFails() {
        let completed = expectation(description: "registration fails")
        let expectedError = NSError(domain: "WarmAlarmTests", code: 2)
        var added = [String]()
        var rolledBack = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                completion(identifier == "42#3" ? expectedError : nil)
            },
            rollback: { identifiers in
                rolledBack = identifiers
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(added, ["42#1", "42#3"])
        XCTAssertEqual(rolledBack, ["42#1", "42#3"])
    }
}

final class WarmAlarmRequestTests: XCTestCase {
    func testListsEveryFallbackIdentifierForCancellation() {
        XCTAssertEqual(
            WarmAlarmPlugin.fallbackIdentifiers(for: 42),
            [
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
    }

    func testListsEveryRequestIdentifierForCancellation() {
        XCTAssertEqual(
            WarmAlarmPlugin.requestIdentifiers(for: 42, recurrenceWeekdays: [2, 4]),
            [
                "42",
                "42#2",
                "42#4",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
    }

    func testBuildsActionableFallbackChainForOneShotAlarm() {
        let schedule = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false)
        )
        let content = UNMutableNotificationContent()
        content.title = "Wake up"
        content.body = "Alarm"
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let requests = WarmAlarmPlugin.makeRequests(for: schedule, content: content)

        XCTAssertEqual(
            requests.map(\.identifier),
            [
                "42",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 7)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            triggers.compactMap { Calendar.current.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970.rounded()) },
            [1_900_000_000, 1_900_000_030, 1_900_000_060, 1_900_000_090, 1_900_000_120, 1_900_000_150,
             1_900_000_180]
        )
        for request in requests {
            XCTAssertEqual(request.content.title, "Wake up")
            XCTAssertEqual(request.content.body, "Alarm")
            XCTAssertEqual(request.content.userInfo["alarmId"] as? String, "42")
            XCTAssertEqual(request.content.categoryIdentifier, "WARM_ALARM")
        }
    }

    func testBuildsFiniteFallbackChainAlongsideRecurringRequests() {
        let schedule = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [2, 4])
        )
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let requests = WarmAlarmPlugin.makeRequests(for: schedule, content: content)

        XCTAssertEqual(
            requests.map(\.identifier),
            [
                "42#2",
                "42#4",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
        XCTAssertTrue(requests.prefix(2).allSatisfy {
            ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true
        })
        let fallbackTriggers = requests.dropFirst(2).compactMap {
            $0.trigger as? UNCalendarNotificationTrigger
        }
        XCTAssertEqual(fallbackTriggers.count, 6)
        XCTAssertTrue(fallbackTriggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            fallbackTriggers.compactMap { Calendar.current.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970.rounded()) },
            [1_900_000_030, 1_900_000_060, 1_900_000_090, 1_900_000_120, 1_900_000_150, 1_900_000_180]
        )
        for request in requests {
            XCTAssertEqual(request.content.userInfo["alarmId"] as? String, "42")
            XCTAssertEqual(request.content.categoryIdentifier, "WARM_ALARM")
        }
    }
}
