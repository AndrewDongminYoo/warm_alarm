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

    func testBuildsFallbackChainForSnoozedOccurrence() {
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
            content: content,
            calendar: utcCalendar()
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
        XCTAssertEqual((requests.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 60)
        XCTAssertEqual(
            requests.dropFirst().compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
                .compactMap { utcCalendar().date(from: $0) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            [
                fireAtMillis + 30_000,
                fireAtMillis + 60_000,
                fireAtMillis + 90_000,
                fireAtMillis + 120_000,
                fireAtMillis + 150_000,
                fireAtMillis + 180_000,
            ]
        )
        XCTAssertTrue(requests.allSatisfy { $0.content.userInfo["alarmId"] as? String == "42" })
        XCTAssertTrue(requests.allSatisfy { $0.content.categoryIdentifier == "WARM_ALARM" })
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
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
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

    func testRecoveryRestoresOnlyStillFutureFallbacksAsOneShots() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
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
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 5)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            triggers.compactMap { utcCalendar().date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            [anchor + 60_000, anchor + 90_000, anchor + 120_000, anchor + 150_000, anchor + 180_000]
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

    func testForegroundOccurrenceTrackerScopesSuppressionToResettableOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, isFallback: false))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, isFallback: true))

        tracker.clear(alarmId: 42)

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, isFallback: true))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, isFallback: true))
    }

    func testForegroundOccurrenceTrackerAtomicallyHandlesOneConcurrentFallback() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        let resultLock = NSLock()
        var handledCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard tracker.shouldHandleAndMark(alarmId: 42, isFallback: true) else { return }
            resultLock.lock()
            handledCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(handledCount, 1)
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
