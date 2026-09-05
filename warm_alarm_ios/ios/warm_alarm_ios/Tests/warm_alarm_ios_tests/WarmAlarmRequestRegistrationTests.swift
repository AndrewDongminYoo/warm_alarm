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

    func testSubmitsEveryRequestBeforeWaitingForCallbacks() {
        var added = [String]()
        var callbacks = [(Error?) -> Void]()
        var didComplete = false

        WarmAlarmRequestRegistration.addAtomically(
            ["42", "42#fallback#1"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                callbacks.append(completion)
            },
            rollback: { _ in
                XCTFail("Successful registration must not roll back requests")
            },
            completion: { error in
                XCTAssertNil(error)
                didComplete = true
            }
        )

        XCTAssertEqual(added, ["42", "42#fallback#1"])
        guard callbacks.count == 2 else { return }
        XCTAssertFalse(didComplete)
        callbacks[0](nil)
        XCTAssertFalse(didComplete)
        callbacks[1](nil)
        XCTAssertTrue(didComplete)
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

final class WarmAlarmSnoozeRegistrationTests: XCTestCase {
    func testCompletesOnMainThreadWhenRegistrationFinishesInBackground() {
        let completed = expectation(description: "snooze registration completes")

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {},
            register: { completion in
                DispatchQueue.global().async {
                    completion(nil, false)
                }
            },
            rollback: { _, _ in
                XCTFail("A successful registration must not roll back the intent")
            },
            completion: { error in
                XCTAssertNil(error)
                XCTAssertTrue(Thread.isMainThread)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
    }

    func testPersistsIntentBeforeRegistrationStarts() {
        var steps = [String]()

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {
                steps.append("persist")
            },
            register: { _ in
                steps.append("register")
            },
            rollback: { _, _ in
                XCTFail("An unfinished registration must not roll back the intent")
            },
            completion: { _ in
                XCTFail("An unfinished registration must not complete")
            }
        )

        XCTAssertEqual(steps, ["persist", "register"])
    }

    func testRollsBackIntentWhenRegistrationReportsFailure() {
        let expectedError = NSError(domain: "WarmAlarmTests", code: 4)
        let completed = expectation(description: "snooze registration completes")
        var steps = [String]()

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {
                steps.append("persist")
            },
            register: { completion in
                steps.append("register")
                completion(expectedError, false)
            },
            rollback: { didSubmitRequests, rollbackCompletion in
                XCTAssertFalse(didSubmitRequests)
                steps.append("rollback")
                rollbackCompletion(nil)
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                steps.append("completion")
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(steps, ["persist", "register", "rollback", "completion"])
    }

    func testReportsRollbackFailure() {
        let registrationError = NSError(domain: "WarmAlarmRegistrationTests", code: 1)
        let rollbackError = NSError(domain: "WarmAlarmRollbackTests", code: 2)
        let completed = expectation(description: "snooze rollback failure completes")

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {},
            register: { completion in
                completion(registrationError, true)
            },
            rollback: { didSubmitRequests, completion in
                XCTAssertTrue(didSubmitRequests)
                completion(rollbackError)
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, rollbackError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
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

        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )

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
            triggers.compactMap { utcCalendar().date(from: $0.dateComponents) }
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

    func testFallbackChainCarriesOneStableOccurrenceTokenWithIsolatedOrdinals() {
        let scheduledAtMillis = Int64(1_900_000_000_000)
        let schedule = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42", "hostPayload": "preserved"]

        let firstRequests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: utcCalendar()
        )
        let secondRequests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: utcCalendar()
        )

        let firstMetadata = firstRequests.compactMap { occurrenceMetadata(from: $0.content) }
        let secondMetadata = secondRequests.compactMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(firstMetadata.count, 7)
        XCTAssertEqual(Set(firstMetadata.compactMap { $0["token"] as? String }).count, 1)
        XCTAssertEqual(firstMetadata.compactMap { $0["ordinal"] as? Int }, Array(0...6))
        XCTAssertTrue(firstRequests.allSatisfy { $0.content.userInfo["alarmId"] as? String == "42" })
        XCTAssertTrue(firstRequests.allSatisfy { $0.content.userInfo["hostPayload"] as? String == "preserved" })
        XCTAssertTrue(firstRequests.allSatisfy {
            PropertyListSerialization.propertyList($0.content.userInfo, isValidFor: .binary)
        })
        XCTAssertEqual(
            firstMetadata.first?["token"] as? String,
            secondMetadata.first?["token"] as? String
        )
    }

    func testBuildsSnoozeFallbackChainWithRelativeIntervals() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: content
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        XCTAssertEqual(
            requests.compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval },
            [60, 90, 120, 150, 180, 210, 240]
        )
        XCTAssertTrue(requests.allSatisfy { $0.content.userInfo["alarmId"] as? String == "42" })
        XCTAssertTrue(requests.allSatisfy { $0.content.categoryIdentifier == "WARM_ALARM" })
        let metadata = requests.compactMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(metadata.count, 7)
        XCTAssertEqual(Set(metadata.compactMap { $0["token"] as? String }).count, 1)
        XCTAssertEqual(metadata.compactMap { $0["ordinal"] as? Int }, Array(0...6))
    }

    func testSnoozeOccurrenceMetadataKeepsFixedEpochAcrossTimeZoneChanges() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: UNMutableNotificationContent()
        )
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 60 * 60)!

        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["floating"] as? Bool == false
        })
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                content: requests[0].content,
                identifier: requests[0].identifier,
                alarmId: 42,
                deliveredAtMillis: fireAtMillis,
                calendar: deliveryCalendar,
                schedule: schedule
            ),
            "warm-alarm-v1:42#\(fireAtMillis)"
        )
    }

    func testBuildsFiniteFallbackChainAlongsideRecurringRequests() {
        let calendar = utcCalendar()
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

        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: 1_899_996_400_000,
            calendar: calendar
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )

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
            fallbackTriggers.compactMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970.rounded()) },
            [1_900_172_790, 1_900_172_820, 1_900_172_850, 1_900_172_880, 1_900_172_910, 1_900_172_940]
        )
        for request in requests {
            XCTAssertEqual(request.content.userInfo["alarmId"] as? String, "42")
            XCTAssertEqual(request.content.categoryIdentifier, "WARM_ALARM")
        }
    }

    func testRecurringPrimaryMetadataKeepsRequestedTimeAcrossDstGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 3, 2, 30, calendar: calendar)
        let schedule = makeWireSchedule(
            scheduledAtMillis: scheduledAtMillis,
            recurrenceWeekdays: [7]
        )
        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 1, 0, calendar: calendar),
            calendar: calendar
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )

        let fallbackTime = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(fallbackAnchorMillis) / 1_000)
        )
        XCTAssertEqual(fallbackTime.hour, 3)
        XCTAssertEqual(fallbackTime.minute, 0)
        let metadata = occurrenceMetadata(from: requests[0].content)
        XCTAssertEqual(metadata?["hour"] as? Int, 2)
        XCTAssertEqual(metadata?["minute"] as? Int, 30)
    }

    func testRecurringFallbackAnchorMovesPastCurrentTime() {
        let calendar = utcCalendar()
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 17, 17, 46, calendar: calendar),
            recurrenceWeekdays: [2, 4]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 20, 18, 0, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 3, 21, 17, 46, calendar: calendar))
    }

    func testRecurringFallbackAnchorMatchesNativeTriggerBeforeFutureScheduledDate() {
        let calendar = utcCalendar()
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 1, 28, 7, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 1, 6, 8, 0, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 1, 7, 7, 0, calendar: calendar))
    }

    func testRecurringFallbackAnchorPreservesLocalTimeAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 10, 1, 30, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 3, 30, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 3, 11, 1, 30, calendar: calendar))
    }

    func testPendingLimitKeepsCoreAndTrimsOnlyNewestFallbackSuffix() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let pending = Set((0..<58).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 1)
        XCTAssertNotNil(WarmAlarmPlugin.fallbackCapacityWarning(
            omittedCount: selection?.omittedFallbackCount ?? 0
        ))
    }

    func testSnoozeCapacityPreservesCoreAndKillWarningReservation() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: UNMutableNotificationContent()
        )
        let fullCoreCapacity = Set((0..<63).map { "existing-\($0)" } + ["42#2"])

        XCTAssertNil(WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: fullCoreCapacity,
            isKillWarningConfigured: false,
            limit: 64
        ))

        let killWarningReserved = WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: Set((0..<62).map { "existing-\($0)" }),
            isKillWarningConfigured: true,
            limit: 64
        )
        XCTAssertEqual(killWarningReserved?.requests.map(\.identifier), ["42"])
        XCTAssertEqual(killWarningReserved?.omittedFallbackCount, 6)

        let pendingWithFallbacks = Set((0..<58).map { "existing-\($0)" })
            .union(WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let replacingFallbacks = WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pendingWithFallbacks,
            isKillWarningConfigured: false,
            limit: 64
        )
        XCTAssertEqual(replacingFallbacks?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(replacingFallbacks?.omittedFallbackCount, 1)
    }

    func testPendingLimitRefusesScheduleWhenCoreDoesNotFit() {
        let schedule = makeWireSchedule(
            scheduledAtMillis: 1_900_000_000_000,
            recurrenceWeekdays: [2, 4]
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: 1_900_172_760_000,
            calendar: utcCalendar()
        )
        let pending = Set((0..<63).map { "existing-\($0)" })

        XCTAssertNil(WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        ))
    }

    func testPendingLimitReusesSlotsFromTheAlarmBeingReplaced() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let replacing = Set(WarmAlarmPlugin.requestIdentifiers(for: 42, recurrenceWeekdays: nil))
        let pending = replacing.union((0..<57).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: replacing,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.count, 7)
        XCTAssertEqual(selection?.omittedFallbackCount, 0)
    }

    func testPendingLimitDeduplicatesRepeatedCoreIdentifiers() {
        let schedule = makeWireSchedule(
            scheduledAtMillis: 1_900_000_000_000,
            recurrenceWeekdays: [2, 2, 2]
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: 1_900_172_760_000,
            calendar: utcCalendar()
        )
        let pending = Set((0..<62).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), ["42#2", "42#fallback#1"])
        XCTAssertEqual(selection?.omittedFallbackCount, 5)
    }

    func testPendingLimitReservesConfiguredKillWarningSlot() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let pending = Set((0..<57).map { "existing-\($0)" })
        let reservedSlotCount = WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: true,
            pendingIdentifiers: pending
        )

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            reservedSlotCount: reservedSlotCount,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 1)
        XCTAssertEqual(WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: false,
            pendingIdentifiers: pending
        ), 0)
        XCTAssertEqual(WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: true,
            pendingIdentifiers: pending.union(["warm_alarm_kill_warning_notif"])
        ), 0)
    }

    func testKillWarningConfigurationRequiresAnAvailableSlot() {
        XCTAssertFalse(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<64).map { "existing-\($0)" }),
            limit: 64
        ))
        XCTAssertTrue(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<63).map { "existing-\($0)" }),
            limit: 64
        ))
        XCTAssertTrue(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<63).map { "existing-\($0)" })
                .union(["warm_alarm_kill_warning_notif"]),
            limit: 64
        ))
    }

    func testRecoveryRestoresOnlyStillFutureFallbacksWithRemainingIntervals() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )
        let content = UNMutableNotificationContent()

        XCTAssertTrue(WarmAlarmPlugin.shouldRecover(
            schedule: schedule,
            nowMillis: anchor + 45_000
        ))

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 45_000,
            pendingIdentifiers: ["42#fallback#1"],
            content: content,
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let triggers = requests.compactMap { $0.trigger as? UNTimeIntervalNotificationTrigger }
        XCTAssertEqual(triggers.count, 5)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(triggers.map(\.timeInterval), [15, 45, 75, 105, 135])
    }

    func testRecoveryKeepsScheduledFallbacksAlignedToCalendar() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor
        )
        let calendar = utcCalendar()

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 45_000,
            pendingIdentifiers: ["42#fallback#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 5)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            triggers.compactMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            [anchor + 60_000, anchor + 90_000, anchor + 120_000, anchor + 150_000, anchor + 180_000]
        )
    }

    func testRecoveryPreservesRecurringWallTimeAfterTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let wire = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [1]
        )
        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: wire,
            nowMillis: millis(2030, 3, 11, 6, 0, calendar: schedulingCalendar),
            calendar: schedulingCalendar
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: schedulingCalendar
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let primaryTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(primaryTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(primaryTrigger?.dateComponents.minute, 0)
        let fallbackTriggers = requests.dropFirst().compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.hour), [7, 7, 7, 7, 7])
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.minute), [1, 1, 2, 2, 3])
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.second), [0, 30, 0, 30, 0])
    }

    func testRecoveryDetectsDateLineChangeWhenRecurringHourIsUnchanged() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(secondsFromGMT: 14 * 60 * 60)!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: schedulingCalendar
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(secondsFromGMT: -10 * 60 * 60)!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstFallback = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(firstFallback?.dateComponents.year, 2030)
        XCTAssertEqual(firstFallback?.dateComponents.month, 3)
        XCTAssertEqual(firstFallback?.dateComponents.day, 11)
        XCTAssertEqual(firstFallback?.dateComponents.hour, 7)
        XCTAssertEqual(firstFallback?.dateComponents.minute, 0)
        XCTAssertEqual(firstFallback?.dateComponents.second, 30)
    }

    func testRecoveryDoesNotAdvanceAnExpiredRecurringFallbackChainWithoutTimeZoneChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 181_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertTrue(requests.isEmpty)
    }

    func testRecoveryRebuildsFallbacksAfterRecurringStopClearsAnchor() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let nextOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).clearingFallbackAnchor()

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 1, 8, 12, 0, calendar: calendar),
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstFallbackTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(
            firstFallbackTrigger.flatMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            nextOccurrenceMillis + 30_000
        )
    }

    func testRecoveryAdvancesPastAnExpiredSnoozeAfterTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: schedulingCalendar
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        XCTAssertEqual(requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.count, 5)
        XCTAssertTrue(requests.compactMap { $0.trigger as? UNTimeIntervalNotificationTrigger }.isEmpty)
    }

    func testRecoveryDoesNotReuseAnExpiredSnoozeAnchorThatMatchesCurrentWallTime() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let snoozeAnchorMillis = scheduledAtMillis + 3 * 60 * 60 * 1_000
        let wire = makeWireSchedule(
            scheduledAtMillis: scheduledAtMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withActiveSnooze(
            untilMillis: snoozeAnchorMillis,
            fallbackAnchorMillis: snoozeAnchorMillis
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: snoozeAnchorMillis + 181_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(firstTrigger?.dateComponents.year, 2030)
        XCTAssertEqual(firstTrigger?.dateComponents.month, 3)
        XCTAssertEqual(firstTrigger?.dateComponents.day, 18)
        XCTAssertEqual(firstTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(firstTrigger?.dateComponents.minute, 0)
        XCTAssertEqual(firstTrigger?.dateComponents.second, 30)
    }

    func testRecoveryKeepsSnoozedPrimaryRelativeToFallbacks() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set(WarmAlarmPlugin.fallbackIdentifiers(for: 42)),
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), ["42"])
        let trigger = requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval, 60)
        XCTAssertEqual(trigger?.repeats, false)
    }

    func testRecoveryBackfillsAnExpiredSelectedFallbackWithinItsSlot() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )

        let refreshedRequests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 31_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )
        let requests = WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
            [refreshedRequests],
            remainingRequestCount: 1
        )

        XCTAssertEqual(requests.map(\.identifier), ["42#fallback#2"])
        let trigger = requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval, 29)
    }

    func testRecoveryReallocatesVacatedSlotsAcrossAlarmGroups() {
        let content = UNMutableNotificationContent()
        let laterFallback = UNNotificationRequest(
            identifier: "84#fallback#2",
            content: content,
            trigger: nil
        )

        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[], [laterFallback]],
                remainingRequestCount: 1
            ).map(\.identifier),
            []
        )
        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[laterFallback]],
                remainingRequestCount: 1
            ).map(\.identifier),
            ["84#fallback#2"]
        )
    }

    func testRecoveryReservesRemainingSlotsForFutureCoreRequests() {
        let content = UNMutableNotificationContent()
        let currentFallback = UNNotificationRequest(
            identifier: "42#fallback#2",
            content: content,
            trigger: nil
        )
        let futureCore = UNNotificationRequest(identifier: "84", content: content, trigger: nil)

        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[currentFallback], [futureCore]],
                remainingRequestCount: 1
            ).map(\.identifier),
            []
        )
    }

    func testRecoveryCapacityPreservesEveryMissingCoreBeforeFallbacks() {
        let anchor = Int64(1_900_000_000_000)
        let pending = Set((0..<60).map { "existing-\($0)" })
        let requestGroups = [Int64(42), 84].map { alarmId in
            let schedule = WarmAlarmScheduleData.from(
                wire: makeWireSchedule(id: alarmId, scheduledAtMillis: anchor),
                fallbackAnchorMillis: anchor
            )
            return WarmAlarmPlugin.makeRecoveryRequests(
                for: schedule,
                nowMillis: anchor - 60_000,
                pendingIdentifiers: pending,
                content: UNMutableNotificationContent(),
                calendar: utcCalendar()
            )
        }

        let selection = WarmAlarmPlugin.selectRecoveryRequestsWithinPendingLimit(
            requestGroups,
            pendingIdentifiers: pending,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "84",
            "42#fallback#1",
            "42#fallback#2",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 10)
    }

    func testRecoveryOrdersTimeZoneShiftedSchedulesByReconstructedOccurrence() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laterWire = makeWireSchedule(
            id: 42,
            scheduledAtMillis: millis(2030, 3, 5, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [2]
        )
        let imminentWire = makeWireSchedule(
            id: 84,
            scheduledAtMillis: millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [1]
        )
        let schedules = [laterWire, imminentWire].map {
            WarmAlarmScheduleData.from(
                wire: $0,
                fallbackAnchorMillis: $0.scheduledAtMillis,
                calendar: schedulingCalendar
            )
        }
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let sorted = WarmAlarmPlugin.sortedRecoverableSchedules(
            schedules,
            nowMillis: millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(sorted.map(\.id), [84, 42])
    }

    func testMigrationPersistsRecurringWallTimeFromPendingTrigger() throws {
        let legacyJSON = """
        {
          "id": 42,
          "scheduledAtMillis": 1900000000000,
          "notificationTitle": "Wake up",
          "notificationBody": "Alarm",
          "recurrenceWeekdays": [1]
        }
        """
        let schedule = try JSONDecoder().decode(
            WarmAlarmScheduleData.self,
            from: Data(legacyJSON.utf8)
        )
        var components = DateComponents()
        components.weekday = 2
        components.hour = 7
        components.minute = 30
        let pendingRequest = UNNotificationRequest(
            identifier: "42#1",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        var saved: [WarmAlarmScheduleData] = []

        let migrated = WarmAlarmPlugin.migrateRecurringWallTimes(
            [schedule],
            pendingRequests: [pendingRequest],
            save: { saved.append($0) }
        )

        XCTAssertEqual(migrated.first?.recurrenceHour, 7)
        XCTAssertEqual(migrated.first?.recurrenceMinute, 30)
        XCTAssertEqual(saved.map(\.id), [42])
        XCTAssertEqual(saved.first?.recurrenceHour, 7)
        XCTAssertEqual(saved.first?.recurrenceMinute, 30)
    }

    func testMigrationPreservesOneShotFallbackWallTimeFromPendingPrimary() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let components = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1_000)
        )
        let pendingRequest = UNNotificationRequest(
            identifier: "42",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingRequest],
            calendar: recoveryCalendar,
            save: { saved.append($0) }
        )

        let expectedAnchor = millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar)
        XCTAssertEqual(migrated.first?.scheduledAtMillis, expectedAnchor)
        XCTAssertEqual(migrated.first?.fallbackAnchorMillis, expectedAnchor)
        XCTAssertEqual(
            migrated.first?.snapshotScheduledAtMillis(
                nowMillis: millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar),
                calendar: recoveryCalendar
            ),
            expectedAnchor
        )
        XCTAssertEqual(saved.first?.scheduledAtMillis, expectedAnchor)
        XCTAssertEqual(saved.first?.fallbackAnchorMillis, expectedAnchor)
    }

    func testMigrationAcceptsMixedFallbackMetadataAfterSubsequentTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstRecoveryCalendar = Calendar(identifier: .gregorian)
        firstRecoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var secondRecoveryCalendar = Calendar(identifier: .gregorian)
        secondRecoveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let firstRecoveredAtMillis = millis(2030, 4, 1, 7, 0, calendar: firstRecoveryCalendar)
        let expectedAnchorMillis = millis(2030, 4, 1, 7, 0, calendar: secondRecoveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let initialSchedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )
        let survivingFallback = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar,
            occurrenceSeriesToken: initialSchedule.occurrenceSeriesToken
        )[1]
        let firstMigratedSchedule = initialSchedule.withOneShotAnchor(firstRecoveredAtMillis)
        let recoveredFallback = WarmAlarmPlugin.makeRecoveryRequests(
            for: firstMigratedSchedule,
            nowMillis: firstRecoveredAtMillis - 60_000,
            pendingIdentifiers: ["42", "42#fallback#1"],
            content: UNMutableNotificationContent(),
            calendar: firstRecoveryCalendar
        )[0]

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [firstMigratedSchedule],
            pendingRequests: [survivingFallback, recoveredFallback],
            calendar: secondRecoveryCalendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, expectedAnchorMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, expectedAnchorMillis)
    }

    func testMigrationLeavesLegacyFallbackOnlyScheduleUnchanged() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let fallbackFireAtMillis = scheduledAtMillis + 30_000
        let fallbackComponents = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(fallbackFireAtMillis) / 1_000)
        )
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: fallbackComponents, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let nowMillis = millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar)
        var saved = [WarmAlarmScheduleData]()

        XCTAssertFalse(WarmAlarmPlugin.shouldRecover(schedule: schedule, nowMillis: nowMillis))

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationLeavesInvalidOccurrenceDateUnchanged() {
        let calendar = utcCalendar()
        let scheduledAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let content = makeOccurrenceContent(
            token: "invalid-occurrence",
            ordinal: 1,
            primaryDate: Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1_000),
            calendar: calendar
        )
        var metadata = occurrenceMetadata(from: content)!
        metadata["month"] = 2
        metadata["day"] = 31
        content.userInfo = ["_warmAlarmOccurrenceV1": metadata]
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2030, month: 1, day: 1, hour: 7, minute: 0, second: 30),
                repeats: false
            )
        )
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationLeavesConflictingPrimaryEpochUnchanged() {
        let calendar = utcCalendar()
        let storedAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let metadataAtMillis = millis(2030, 1, 2, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: storedAtMillis),
            fallbackAnchorMillis: storedAtMillis
        )
        let content = makeOccurrenceContent(
            token: "conflicting-occurrence",
            ordinal: 1,
            primaryDate: Date(timeIntervalSince1970: Double(metadataAtMillis) / 1_000),
            calendar: calendar
        )
        var metadata = occurrenceMetadata(from: content)!
        metadata["primaryEpochMillis"] = metadataAtMillis + 24 * 60 * 60 * 1_000
        content.userInfo = ["_warmAlarmOccurrenceV1": metadata]
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2030, month: 1, day: 2, hour: 7, minute: 0, second: 30),
                repeats: false
            )
        )
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationUsesEmbeddedPrimaryWallTimeAcrossDstJump() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let primaryDate = schedulingCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        let scheduledAtMillis = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            occurrenceSeriesToken: "dst-occurrence"
        )
        let fallbackDate = primaryDate.addingTimeInterval(30)
        let fallbackComponents = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fallbackDate
        )
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "dst-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(dateMatching: fallbackComponents, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Phoenix")!

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { _ in }
        )[0]

        let expectedPrimaryDate = recoveryCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        XCTAssertEqual(migrated.scheduledAtMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
        XCTAssertEqual(migrated.fallbackAnchorMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
    }

    func testMigrationKeepsGregorianWallTimeWhenPreferredCalendarChanges() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let primaryDate = schedulingCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        let scheduledAtMillis = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            occurrenceSeriesToken: "calendar-occurrence"
        )
        let fallbackDate = primaryDate.addingTimeInterval(30)
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "calendar-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: schedulingCalendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fallbackDate
                ),
                repeats: false
            )
        )
        var recoveryCalendar = Calendar(identifier: .buddhist)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Phoenix")!

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { _ in }
        )[0]

        var expectedCalendar = Calendar(identifier: .gregorian)
        expectedCalendar.timeZone = recoveryCalendar.timeZone
        let expectedPrimaryDate = expectedCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        XCTAssertEqual(migrated.scheduledAtMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
        XCTAssertEqual(migrated.fallbackAnchorMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
    }

    func testMigrationPreservesRepeatedHourSelectionFromPrimaryEpoch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2030, month: 11, day: 3, hour: 0))!
        let matchingComponents = DateComponents(hour: 1, minute: 30, second: 0)
        let firstOccurrence = calendar.nextDate(
            after: midnight,
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
        let lastOccurrence = calendar.nextDate(
            after: midnight,
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .last,
            direction: .forward
        )!
        XCTAssertNotEqual(firstOccurrence, lastOccurrence)
        let firstOccurrenceMillis = Int64(firstOccurrence.timeIntervalSince1970 * 1_000)
        let lastOccurrenceMillis = Int64(lastOccurrence.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: firstOccurrenceMillis),
            fallbackAnchorMillis: firstOccurrenceMillis,
            occurrenceSeriesToken: "repeated-hour-occurrence"
        )
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "repeated-hour-occurrence",
                ordinal: 1,
                primaryDate: lastOccurrence,
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: lastOccurrence.addingTimeInterval(30)
                ),
                repeats: false
            )
        )

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, lastOccurrenceMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, lastOccurrenceMillis)
    }

    func testRecoveryRequestsPreserveSurvivingOccurrenceToken() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            occurrenceSeriesToken: "surviving-occurrence"
        )
        let calendar = utcCalendar()
        let primaryDate = Date(timeIntervalSince1970: Double(anchor) / 1_000)
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "surviving-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: primaryDate.addingTimeInterval(30)
                ),
                repeats: false
            )
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [fallback.identifier],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "surviving-occurrence"
        })
    }

    func testRecoveryRejectsPendingRequestsFromReplacedGeneration() {
        let anchor = Int64(1_900_000_000_000)
        let calendar = utcCalendar()
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            occurrenceSeriesToken: "new-generation"
        )
        let oldFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "old-generation",
                ordinal: 1,
                primaryDate: Date(timeIntervalSince1970: Double(anchor) / 1_000),
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(anchor + 30_000) / 1_000)
                ),
                repeats: false
            )
        )

        let staleIdentifiers = WarmAlarmPlugin.staleRecoveryRequestIdentifiers(
            for: [schedule],
            in: [oldFallback]
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set([oldFallback.identifier]).subtracting(staleIdentifiers),
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(staleIdentifiers, [oldFallback.identifier])
        XCTAssertTrue(requests.map(\.identifier).contains(oldFallback.identifier))
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "new-generation"
        })
    }

    func testSnapshotsRemainingSnoozeFallbacksAfterPrimaryFires() {
        let snoozeAtMillis = Int64(1_900_000_300_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: snoozeAtMillis - 300_000),
            fallbackAnchorMillis: snoozeAtMillis - 300_000,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let fallbackRequests = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let snapshot = WarmAlarmPlugin.pendingSnoozeRequests(
            for: schedule,
            in: fallbackRequests
        )

        XCTAssertEqual(snapshot.map(\.identifier), fallbackRequests.map(\.identifier))
    }

    func testSnoozeRollbackRecalculatesRemainingFallbackDelay() {
        let snoozeAtMillis = Int64(1_900_000_300_000)
        let calendar = utcCalendar()
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: snoozeAtMillis - 300_000),
            fallbackAnchorMillis: snoozeAtMillis - 300_000,
            calendar: calendar,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let originalRequests = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let rollbackRequests = WarmAlarmPlugin.makeSnoozeRollbackRequests(
            for: schedule,
            restoring: originalRequests,
            nowMillis: snoozeAtMillis + 30_000,
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(rollbackRequests.first?.identifier, "42#fallback#2")
        XCTAssertEqual(
            (rollbackRequests.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval,
            30
        )
    }

    func testSnoozeRollbackDoesNotAdvanceExpiredChainToNextRecurrence() {
        let calendar = utcCalendar()
        let snoozeAtMillis = millis(2030, 1, 7, 7, 5, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: millis(2030, 1, 7, 7, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: wire.scheduledAtMillis,
            calendar: calendar,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let originalFallbacks = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let rollbackRequests = WarmAlarmPlugin.makeSnoozeRollbackRequests(
            for: schedule,
            restoring: originalFallbacks,
            nowMillis: snoozeAtMillis + 181_000,
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertTrue(rollbackRequests.isEmpty)
    }

    func testOneShotMigrationIgnoresPendingRequestsFromReplacedGeneration() {
        let calendar = utcCalendar()
        let storedAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let oldAtMillis = millis(2030, 1, 2, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: storedAtMillis),
            fallbackAnchorMillis: storedAtMillis,
            occurrenceSeriesToken: "new-generation"
        )
        let oldPrimary = UNNotificationRequest(
            identifier: "42",
            content: makeOccurrenceContent(
                token: "old-generation",
                ordinal: 0,
                primaryDate: Date(timeIntervalSince1970: Double(oldAtMillis) / 1_000),
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(oldAtMillis) / 1_000)
                ),
                repeats: false
            )
        )

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [oldPrimary],
            calendar: calendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, storedAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, storedAtMillis)
    }

    func testRecoveryRetainsSeriesTokenWhenRepeatingPrimaryUsesPreviousAnchorMetadata() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let previousAnchorMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: previousAnchorMillis,
                recurrenceWeekdays: [1]
            ),
            fallbackAnchorMillis: previousAnchorMillis,
            calendar: schedulingCalendar,
            occurrenceSeriesToken: "recurring-series"
        )
        let repeatingPrimary = UNNotificationRequest(
            identifier: "42#1",
            content: makeOccurrenceContent(
                token: "recurring-series",
                ordinal: 0,
                primaryDate: Date(timeIntervalSince1970: Double(previousAnchorMillis) / 1_000),
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 7, minute: 0, weekday: 2),
                repeats: true
            )
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nowMillis = millis(2030, 3, 18, 7, 0, calendar: recoveryCalendar) + 45_000
        let firstRecovery = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: nowMillis,
            pendingIdentifiers: [repeatingPrimary.identifier],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )
        let survivingFallback = firstRecovery[0]

        let secondRecovery = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: nowMillis,
            pendingIdentifiers: [repeatingPrimary.identifier, survivingFallback.identifier],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertFalse(secondRecovery.isEmpty)
        XCTAssertTrue(secondRecovery.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "recurring-series"
        })
    }

    func testRecoveryAddsStableMetadataWhenOnlyLegacyPrimaryIsPending() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let legacyPrimary = UNNotificationRequest(
            identifier: "42",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(anchor) / 1_000)
                ),
                repeats: false
            )
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [legacyPrimary.identifier],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(requests.compactMap { occurrenceMetadata(from: $0.content) }.count, requests.count)
        let legacyPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: legacyPrimary.content,
            identifier: legacyPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 5_000,
            calendar: calendar,
            schedule: schedule
        )
        let recoveredFallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: requests[0].content,
            identifier: requests[0].identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000,
            calendar: calendar,
            schedule: schedule
        )
        XCTAssertEqual(legacyPrimaryToken, recoveredFallbackToken)
    }

    func testRecoveryUsesStableMetadataAcrossRecurringAndSnoozeRequests() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let snoozeAtMillis = anchor + 60_000
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let snoozeRequests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: anchor,
            content: UNMutableNotificationContent()
        )
        let pendingRequests = [snoozeRequests[0], snoozeRequests[1]]

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor,
            pendingIdentifiers: Set(pendingRequests.map(\.identifier)),
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let snoozeToken = occurrenceMetadata(from: snoozeRequests[0].content)?["token"] as? String
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == snoozeToken
        })
        let recurrenceTime = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(anchor) / 1_000)
        )
        let recoveredRecurrenceMetadata = requests.first { $0.identifier == "42#1" }
            .flatMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(recoveredRecurrenceMetadata?["hour"] as? Int, recurrenceTime.hour)
        XCTAssertEqual(recoveredRecurrenceMetadata?["minute"] as? Int, recurrenceTime.minute)
    }

    func testRecoveredRecurrenceMetadataKeepsRequestedTimeAcrossDstGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 3, 2, 30, calendar: calendar)
        let snoozeAtMillis = millis(2030, 3, 10, 1, 5, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: scheduledAtMillis,
                recurrenceWeekdays: [7]
            ),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 1, 0, calendar: calendar),
            pendingIdentifiers: ["42"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let metadata = requests.first { $0.identifier == "42#7" }
            .flatMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(metadata?["hour"] as? Int, 2)
        XCTAssertEqual(metadata?["minute"] as? Int, 30)
    }

    func testRecoveryReusesInitialTokenWhenNoRequestsRemainPending() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let wire = makeWireSchedule(scheduledAtMillis: anchor)
        let initialRequests = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )

        let recoveredRequests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let initialToken = occurrenceMetadata(from: initialRequests[0].content)?["token"] as? String
        XCTAssertFalse(recoveredRequests.isEmpty)
        XCTAssertTrue(recoveredRequests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == initialToken
        })
    }

    func testForegroundOccurrenceTrackerScopesSuppressionToResettableOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))

        tracker.clear(alarmId: 42)

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
    }

    func testDelayedPrimaryDoesNotRepeatFallbackAlreadyHandledForSameOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
    }

    func testOlderOccurrenceRemainsSuppressedAfterNewerOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
    }

    func testOldestOccurrenceRemainsSuppressedAfterMoreThanPendingLimitOccurrences() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        for occurrence in 1...65 {
            XCTAssertTrue(tracker.shouldHandleAndMark(
                alarmId: 42,
                occurrenceToken: "series#\(occurrence)"
            ))
        }

        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1"))
    }

    func testStopSuppressesLateFallbackUntilNextPrimaryOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
    }

    func testStopOnFallbackAbsorbsDelayedPrimaryBeforeNextOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
    }

    func testStopRejectsOlderOccurrenceButAllowsCurrentOccurrenceAction() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var stoppedOccurrences = [String]()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            stoppedOccurrences.append("older")
        }
        tracker.stop(alarmId: 42, occurrenceToken: "series#2000") {
            stoppedOccurrences.append("current")
        }

        XCTAssertEqual(stoppedOccurrences, ["current"])
    }

    func testStopConsumesCurrentOccurrenceOnlyOnce() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var actionCount = 0

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            actionCount += 1
        }
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 1)
    }

    func testConsumedOccurrenceSurvivesTrackerReinitialization() {
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)
        var actionCount = 0

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }
        let reinitializedTracker = WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store)
        reinitializedTracker.stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 1)

        reinitializedTracker.clear(alarmId: 42)
        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 2)
    }

    func testConsumedOccurrenceSuppressesRetainedNotificationAfterTrackerReinitialization() {
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        )
        let reinitializedTracker = WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store)

        XCTAssertFalse(reinitializedTracker.shouldHandleAndMark(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ))
        XCTAssertTrue(reinitializedTracker.shouldHandleAndMark(
            alarmId: 42,
            occurrenceToken: "series#2000"
        ))
    }

    func testStopRejectsOccurrenceBeforePersistedScheduleAnchorAfterTrackerReinitialization() {
        let calendar = utcCalendar()
        let currentAnchorMillis = Int64(2_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: currentAnchorMillis),
            fallbackAnchorMillis: currentAnchorMillis,
            calendar: calendar
        )
        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            nowMillis: currentAnchorMillis,
            calendar: calendar
        )
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var didRunAction = false

        tracker.stop(
            alarmId: 42,
            occurrenceToken: "series#1000",
            minimumOccurrenceMillis: minimumOccurrenceMillis
        ) {
            didRunAction = true
        }

        XCTAssertFalse(didRunAction)
    }

    func testRecurringActionRejectsRetainedOccurrenceAfterFallbackAnchorCleared() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let retainedOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let latestOccurrenceMillis = millis(2030, 1, 21, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: firstOccurrenceMillis,
                recurrenceWeekdays: [1]
            ),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).clearingFallbackAnchor()
        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            nowMillis: latestOccurrenceMillis + 1_000,
            calendar: calendar
        )
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)
        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#\(firstOccurrenceMillis)"
        )
        var didRunAction = false

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#\(retainedOccurrenceMillis)",
            minimumOccurrenceMillis: minimumOccurrenceMillis
        ) {
            didRunAction = true
        }

        XCTAssertEqual(minimumOccurrenceMillis, latestOccurrenceMillis)
        XCTAssertFalse(didRunAction)
    }

    func testRecurringActionBoundIgnoresLaterActiveSnoozeChain() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let interveningOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = millis(2030, 1, 21, 7, 30, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let recurringContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        )[0].content

        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            content: recurringContent,
            nowMillis: interveningOccurrenceMillis + 1_000,
            calendar: calendar
        )

        XCTAssertEqual(minimumOccurrenceMillis, interveningOccurrenceMillis)
    }

    func testRecurringActionBoundKeepsExpiredSnoozeNotificationWithinItsOccurrence() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = firstOccurrenceMillis + 5 * 60 * 1_000
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let snoozeContent = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeOccurrenceMillis,
            nowMillis: firstOccurrenceMillis,
            content: UNMutableNotificationContent()
        )[0].content

        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            content: snoozeContent,
            nowMillis: snoozeOccurrenceMillis + 181_000,
            calendar: calendar
        )

        XCTAssertEqual(minimumOccurrenceMillis, snoozeOccurrenceMillis)
    }

    func testStoppingRecurringOccurrencePreservesLaterSnoozeFallbackChain() {
        let alarmId = Int64(4_242_424_244)
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let interveningOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = millis(2030, 1, 21, 7, 30, calendar: calendar)
        let wire = makeWireSchedule(
            id: alarmId,
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let recurringContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        )[0].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)
        let delegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.recurring_stop_snooze")
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "warm-alarm-v1:\(alarmId)#\(interveningOccurrenceMillis)",
            deliveredIdentifier: "\(alarmId)#1",
            content: recurringContent
        )

        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, snoozeOccurrenceMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, snoozeOccurrenceMillis)
    }

    func testRejectedReplacedOccurrenceStillStopsMatchingPlayingAudio() {
        let alarmId = Int64(4_242_424_242)
        let oldOccurrenceMillis = Int64(1_000)
        let replacementOccurrenceMillis = Int64(2_000)
        let oldWire = makeWireSchedule(id: alarmId, scheduledAtMillis: oldOccurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: oldWire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: oldOccurrenceMillis,
            calendar: utcCalendar()
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: replacementOccurrenceMillis
            ),
            fallbackAnchorMillis: replacementOccurrenceMillis,
            calendar: utcCalendar()
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_occurrence"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "series#\(oldOccurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "series#\(oldOccurrenceMillis)",
            content: oldContent
        )

        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertNil(delegate.currentlyPlayingOccurrenceToken)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, replacementOccurrenceMillis)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testRejectedReplacedOccurrenceSnoozeStopsMatchingPlayingAudio() {
        let alarmId = Int64(4_242_424_243)
        let oldOccurrenceMillis = Int64(1_000)
        let replacementOccurrenceMillis = Int64(2_000)
        let oldWire = makeWireSchedule(id: alarmId, scheduledAtMillis: oldOccurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: oldWire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: oldOccurrenceMillis,
            calendar: utcCalendar()
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: replacementOccurrenceMillis
            ),
            fallbackAnchorMillis: replacementOccurrenceMillis,
            calendar: utcCalendar()
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_snooze_occurrence"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "series#\(oldOccurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        var didComplete = false

        delegate.handleSnooze(
            alarmId: alarmId,
            occurrenceToken: "series#\(oldOccurrenceMillis)",
            content: oldContent
        ) {
            didComplete = true
        }

        XCTAssertTrue(didComplete)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertNil(delegate.currentlyPlayingOccurrenceToken)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, replacementOccurrenceMillis)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testReplacedGenerationRejectsOldNotificationAtSameOccurrence() {
        let alarmId = Int64(4_242_424_245)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "old-generation"
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "new-generation"
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_generation"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "old-generation#\(occurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "old-generation#\(occurrenceMillis)",
            content: oldContent
        )

        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.occurrenceSeriesToken, "new-generation")
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testForegroundDeliveryWaitsForQueuedScheduleReplacement() {
        let alarmId = Int64(4_242_424_246)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let oldSchedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "old-generation"
        )
        let replacement = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "new-generation"
        )
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: oldSchedule.occurrenceSeriesToken
        )[0].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(oldSchedule)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.foreground_delivery_replacement")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        let replacementCompleted = expectation(description: "replacement completes")
        let deliveryCompleted = expectation(description: "delivery completes")
        var didHandle = true

        mutationQueue.enqueueOnMain { finish in
            WarmAlarmStore.shared.save(replacement)
            replacementCompleted.fulfill()
            finish()
        }
        delegate.handleForegroundDelivery(
            alarmId: alarmId,
            identifier: String(alarmId),
            content: oldContent,
            deliveredAtMillis: occurrenceMillis
        ) { handled in
            didHandle = handled
            deliveryCompleted.fulfill()
        }

        wait(for: [replacementCompleted, deliveryCompleted], timeout: 1)
        XCTAssertFalse(didHandle)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testForegroundDeliveryRejectsCanceledAlarmAfterQueuedCancellation() {
        let alarmId = Int64(4_242_424_247)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar()
        )
        let content = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: schedule.occurrenceSeriesToken
        )[1].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.foreground_delivery_cancellation")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        let cancellationCompleted = expectation(description: "cancellation completes")
        let deliveryCompleted = expectation(description: "delivery completes")
        var didHandle = true

        mutationQueue.enqueueOnMain { finish in
            WarmAlarmStore.shared.remove(id: alarmId)
            cancellationCompleted.fulfill()
            finish()
        }
        delegate.handleForegroundDelivery(
            alarmId: alarmId,
            identifier: "\(alarmId)#fallback#1",
            content: content,
            deliveredAtMillis: occurrenceMillis
        ) { handled in
            didHandle = handled
            deliveryCompleted.fulfill()
        }

        wait(for: [cancellationCompleted, deliveryCompleted], timeout: 1)
        XCTAssertFalse(didHandle)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testOccurrenceGenerationsAreUniqueForTheSameAlarm() {
        let first = WarmAlarmPlugin.newOccurrenceSeriesToken(for: 42)
        let second = WarmAlarmPlugin.newOccurrenceSeriesToken(for: 42)

        XCTAssertTrue(first.hasPrefix("warm-alarm-v1:42:"))
        XCTAssertTrue(second.hasPrefix("warm-alarm-v1:42:"))
        XCTAssertNotEqual(first, second)
    }

    func testFloatingOneShotActionBoundFollowsNotificationAcrossTimeZones() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let deliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: deliveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )
        let primaryRequest = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )[0]
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primaryRequest.content,
            identifier: primaryRequest.identifier,
            alarmId: 42,
            deliveredAtMillis: deliveredOccurrenceMillis,
            calendar: deliveryCalendar,
            schedule: schedule
        )

        XCTAssertEqual(occurrenceToken, "warm-alarm-v1:42#\(deliveredOccurrenceMillis)")
        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: primaryRequest.content,
                nowMillis: deliveredOccurrenceMillis,
                calendar: deliveryCalendar
            ),
            deliveredOccurrenceMillis
        )
    }

    func testFloatingOneShotActionBoundFollowsNotificationAcrossSubsequentTimeZoneChanges() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstDeliveryCalendar = Calendar(identifier: .gregorian)
        firstDeliveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var secondDeliveryCalendar = Calendar(identifier: .gregorian)
        secondDeliveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let firstDeliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: firstDeliveryCalendar)
        let secondDeliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: secondDeliveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withOneShotAnchor(firstDeliveredOccurrenceMillis)
        let primaryRequest = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )[0]
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primaryRequest.content,
            identifier: primaryRequest.identifier,
            alarmId: 42,
            deliveredAtMillis: secondDeliveredOccurrenceMillis,
            calendar: secondDeliveryCalendar,
            schedule: schedule
        )

        XCTAssertEqual(occurrenceToken, "warm-alarm-v1:42#\(secondDeliveredOccurrenceMillis)")
        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: primaryRequest.content,
                nowMillis: secondDeliveredOccurrenceMillis,
                calendar: secondDeliveryCalendar
            ),
            secondDeliveredOccurrenceMillis
        )
    }

    func testRecoveredOneShotActionBoundFollowsNotificationAcrossSubsequentTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstRecoveryCalendar = Calendar(identifier: .gregorian)
        firstRecoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let recoveredAtMillis = millis(2030, 4, 1, 7, 0, calendar: firstRecoveryCalendar)
        let deliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: deliveryCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withOneShotAnchor(recoveredAtMillis)
        let recoveredRequest = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: recoveredAtMillis - 60_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: firstRecoveryCalendar
        )[0]

        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: recoveredRequest.content,
                nowMillis: deliveredOccurrenceMillis,
                calendar: deliveryCalendar
            ),
            deliveredOccurrenceMillis
        )
    }

    func testStoppedOccurrenceDoesNotSuppressFallbackFromNextOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertTrue(tracker.handleIfAllowed(
            alarmId: 42,
            occurrenceToken: "series#2000",
            perform: {}
        ))
    }

    func testForegroundOccurrenceTokenEncodesFallbackAnchor() {
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                identifier: "42#fallback#3",
                alarmId: 42,
                deliveredAtMillis: 91_000
            ),
            "1000"
        )
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                identifier: "42#1",
                alarmId: 42,
                deliveredAtMillis: 91_000
            ),
            "91000"
        )
    }

    func testForegroundOccurrenceTokenIgnoresNotificationDeliveryLatency() {
        let anchor = Int64(1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: makeWireSchedule(scheduledAtMillis: anchor),
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: utcCalendar()
        )
        let primary = requests[0]
        let fallback = requests[1]

        let primaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primary.content,
            identifier: primary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 1_000
        )
        let fallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: fallback.content,
            identifier: fallback.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000
        )

        XCTAssertEqual(primaryToken, fallbackToken)
    }

    func testRecurringPrimaryUsesAStableTokenForEachWallOccurrence() {
        let calendar = utcCalendar()
        let primaryDate = calendar.date(from: DateComponents(
            year: 2030,
            month: 1,
            day: 7,
            hour: 7,
            minute: 0
        ))!
        let appleWeekday = calendar.component(.weekday, from: primaryDate)
        let isoWeekday = Int64(appleWeekday == 1 ? 7 : appleWeekday - 1)
        let anchor = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: makeWireSchedule(
                scheduledAtMillis: anchor,
                recurrenceWeekdays: [isoWeekday]
            ),
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let recurringPrimary = requests[0]
        let fallback = requests[1]

        let initialPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: recurringPrimary.content,
            identifier: recurringPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 5_000,
            calendar: calendar
        )
        let initialFallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: fallback.content,
            identifier: fallback.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000,
            calendar: calendar
        )
        let nextPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: recurringPrimary.content,
            identifier: recurringPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 7 * 24 * 60 * 60 * 1_000 + 5_000,
            calendar: calendar
        )

        XCTAssertEqual(initialPrimaryToken, initialFallbackToken)
        XCTAssertNotEqual(nextPrimaryToken, initialFallbackToken)
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: initialFallbackToken))
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: nextPrimaryToken))
    }

    func testForegroundOccurrenceTrackerAtomicallyHandlesOneConcurrentFallback() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        let resultLock = NSLock()
        var handledCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000") else { return }
            resultLock.lock()
            handledCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(handledCount, 1)
    }

    func testStopWaitsForAdmittedFallbackWorkBeforeCompleting() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        let fallbackEntered = DispatchSemaphore(value: 0)
        let releaseFallback = DispatchSemaphore(value: 0)
        let fallbackCompleted = DispatchSemaphore(value: 0)
        let stopStarted = DispatchSemaphore(value: 0)
        let stopCompleted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000") {
                fallbackEntered.signal()
                releaseFallback.wait()
            }
            fallbackCompleted.signal()
        }
        XCTAssertEqual(fallbackEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            stopStarted.signal()
            tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})
            stopCompleted.signal()
        }
        XCTAssertEqual(stopStarted.wait(timeout: .now() + 1), .success)
        let stopResultBeforeRelease = stopCompleted.wait(timeout: .now() + 0.1)

        releaseFallback.signal()
        XCTAssertEqual(fallbackCompleted.wait(timeout: .now() + 1), .success)
        if stopResultBeforeRelease == .timedOut {
            XCTAssertEqual(stopCompleted.wait(timeout: .now() + 1), .success)
        }
        XCTAssertEqual(stopResultBeforeRelease, .timedOut)
    }

    func testRecoveryRequestsDeduplicateRepeatedWeekdays() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: anchor,
                recurrenceWeekdays: [2, 2, 2]
            ),
            fallbackAnchorMillis: anchor
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set(WarmAlarmPlugin.fallbackIdentifiers(for: 42)),
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), ["42#2"])
    }

    func testDismissalRemovesEveryDeliveredIdentifierForTheExactAlarm() {
        XCTAssertEqual(
            WarmAlarmDelegate.deliveredIdentifiersToRemove(
                alarmId: 42,
                recurrenceWeekdays: [2, 4],
                deliveredIdentifier: "42#fallback#3"
            ),
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

    private func makeWireSchedule(
        id: Int64 = 42,
        scheduledAtMillis: Int64,
        recurrenceWeekdays: [Int64]? = nil
    ) -> WarmAlarmScheduleWire {
        WarmAlarmScheduleWire(
            id: id,
            scheduledAtMillis: scheduledAtMillis,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) }
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeOccurrenceContent(
        token: String,
        ordinal: Int,
        primaryDate: Date,
        calendar: Calendar
    ) -> UNMutableNotificationContent {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: primaryDate
        )
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "_warmAlarmOccurrenceV1": [
                "token": token,
                "ordinal": ordinal,
                "year": components.year!,
                "month": components.month!,
                "day": components.day!,
                "hour": components.hour!,
                "minute": components.minute!,
                "second": components.second!,
                "calendar": "gregorian",
                "floating": true,
                "timeZone": calendar.timeZone.identifier,
                "primaryEpochMillis": Int64(primaryDate.timeIntervalSince1970 * 1_000),
            ],
        ]
        return content
    }

    private func occurrenceMetadata(from content: UNNotificationContent) -> [String: Any]? {
        content.userInfo["_warmAlarmOccurrenceV1"] as? [String: Any]
    }

    private func millis(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Int64 {
        let date = calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
        return Int64(date.timeIntervalSince1970 * 1_000)
    }
}

private final class RecordingWarmAlarmEventsApi: WarmAlarmEventsApiProtocol {
    private(set) var events = [WarmAlarmEventWire]()

    func emitEvent(
        event: WarmAlarmEventWire,
        completion: @escaping (Result<Void, PigeonError>) -> Void
    ) {
        events.append(event)
        completion(.success(()))
    }
}
