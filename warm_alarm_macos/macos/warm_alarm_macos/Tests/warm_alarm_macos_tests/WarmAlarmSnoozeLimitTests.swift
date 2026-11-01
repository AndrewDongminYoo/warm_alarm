import AVFoundation
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmSnoozeLimitTests: XCTestCase {
    // MARK: - Categories

    func testStopOnlyCategoryIsOwnedAndOffersOnlyStop() throws {
        let fixture = try fixture()
        let defaultStopOnly = WarmAlarmDelegate.notificationCategory(stopTitle: nil, snoozeTitle: nil, offersSnooze: false)
        let customStopOnly = WarmAlarmDelegate.notificationCategory(
            stopTitle: "Dismiss", snoozeTitle: "Later", offersSnooze: false
        )
        let customWithSnooze = WarmAlarmDelegate.notificationCategory(stopTitle: "Dismiss", snoozeTitle: "Later")

        XCTAssertEqual(defaultStopOnly.actions.map(\.identifier), ["STOP"])
        XCTAssertEqual(defaultStopOnly.actions.map(\.title), ["Stop"])
        XCTAssertEqual(customStopOnly.actions.map(\.title), ["Dismiss"])
        XCTAssertEqual(customWithSnooze.actions.map(\.identifier), ["STOP", "SNOOZE"])
        XCTAssertEqual(
            Set([
                WarmAlarmDelegate.categoryIdentifier,
                defaultStopOnly.identifier,
                customStopOnly.identifier,
                customWithSnooze.identifier,
            ]).count,
            4
        )
        XCTAssertEqual(
            WarmAlarmDelegate.notificationCategory(stopTitle: "Dismiss", snoozeTitle: "Other", offersSnooze: false)
                .identifier,
            customStopOnly.identifier
        )
        XCTAssertTrue(WarmAlarmDelegate.ownsCategory(defaultStopOnly.identifier))
        XCTAssertTrue(WarmAlarmDelegate.ownsCategory(customStopOnly.identifier))
        XCTAssertFalse(WarmAlarmDelegate.ownsCategory("WARM_ALARM:HOST_MESSAGES"))
        let stopOnlyContent = UNMutableNotificationContent()
        stopOnlyContent.categoryIdentifier = customStopOnly.identifier
        let proxy = WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: fixture.delegate, forwardingDelegate: nil)
        XCTAssertTrue(proxy.target(for: stopOnlyContent) === fixture.delegate)
    }

    func testContentOffersSnoozeUntilTheCountReachesMaxCount() throws {
        let fixture = try fixture()
        let cases: [(maxCount: Int64?, count: Int64, offersSnooze: Bool)] = [
            (nil, 0, true), (nil, 7, true), (0, 0, false), (2, 0, true), (2, 1, true), (2, 2, false), (2, 3, false),
        ]
        for testCase in cases {
            var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: testCase.maxCount))
            schedule.snoozeCount = testCase.count
            let content = fixture.delegate.makeContent(from: schedule)
            let message = "maxCount \(String(describing: testCase.maxCount)), count \(testCase.count)"

            XCTAssertEqual(
                registeredActionIdentifiers(for: [content]).first,
                testCase.offersSnooze ? ["STOP", "SNOOZE"] : ["STOP"],
                message
            )
            XCTAssertEqual(content.userInfo["warmAlarmStopOnly"] as? Bool == true, !testCase.offersSnooze, message)
        }
    }

    func testRegistrationRebuildsStopOnlyAndLegacyCategoriesFromContent() throws {
        let fixture = try fixture()
        let stopOnly = fixture.delegate.makeContent(from: WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 0)))
        let legacy = UNMutableNotificationContent()
        legacy.categoryIdentifier = WarmAlarmDelegate.notificationCategory(stopTitle: "Dismiss", snoozeTitle: "Later")
            .identifier
        legacy.userInfo = [
            "alarmId": String(fixture.alarmId),
            "warmAlarmStopActionTitle": "Dismiss",
            "warmAlarmSnoozeActionTitle": "Later",
        ]
        XCTAssertNotEqual(stopOnly.categoryIdentifier, legacy.categoryIdentifier)
        let proxy = WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: fixture.delegate, forwardingDelegate: nil)
        XCTAssertTrue(proxy.target(for: stopOnly) === fixture.delegate)
        var registered: Set<UNNotificationCategory> = []
        let done = expectation(description: "categories registered")

        WarmAlarmDelegate.registerCategories(
            for: [stopOnly, legacy], read: { $0(registered) }, write: { registered = $0 }
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        let stopOnlyCategory = try XCTUnwrap(registered.first { $0.identifier == stopOnly.categoryIdentifier })
        let legacyCategory = try XCTUnwrap(registered.first { $0.identifier == legacy.categoryIdentifier })
        XCTAssertEqual(stopOnlyCategory.actions.map(\.title), ["Dismiss"])
        XCTAssertEqual(legacyCategory.actions.map(\.title), ["Dismiss", "Later"])
    }

    // MARK: - Scheduling

    func testInitialRequestsOmitSnoozeOnlyWhenMaxCountIsZero() throws {
        let fixture = try fixture()
        let recurrences: [[Int64]?] = [nil, [1, 3]]
        let limits: [(maxCount: Int64?, offersSnooze: Bool)] = [(nil, true), (0, false), (1, true)]
        for recurrence in recurrences {
            for limit in limits {
                fixture.added.removeAll()
                let message = "recurrence \(String(describing: recurrence)), maxCount \(String(describing: limit.maxCount))"

                try schedule(fixture.wire(recurrenceWeekdays: recurrence, maxCount: limit.maxCount), with: fixture)

                XCTAssertEqual(fixture.added.count, recurrence?.count ?? 1, message)
                XCTAssertEqual(
                    Set(registeredActionIdentifiers(for: fixture.added.map(\.content))),
                    [limit.offersSnooze ? ["STOP", "SNOOZE"] : ["STOP"]],
                    message
                )
            }
        }
    }

    func testSchedulingAgainAndCancellingResetTheSnoozeCount() throws {
        let fixture = try fixture()
        var stale = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 2))
        stale.snoozeMaxCount = 2
        stale.snoozeCount = 2
        WarmAlarmStore.shared.save(stale)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeCount, 2, "precondition: the count is stored")

        try schedule(fixture.wire(maxCount: 3), with: fixture)

        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeCount, 0)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeMaxCount, 3)
        var snoozed = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.alarmId))
        snoozed.snoozeCount = 1
        WarmAlarmStore.shared.save(snoozed)
        let cancelled = expectation(description: "cancel completes")
        fixture.plugin.cancelAlarm(id: fixture.alarmId) { result in
            if case let .failure(error) = result { XCTFail("Cancel failed: \(error)") }
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.alarmId))
    }

    func testScheduledAlarmSnapshotsReturnTheSnoozeMaxCount() throws {
        let fixture = try fixture()
        WarmAlarmStore.shared.save(WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 3)))
        var snapshots = [WarmAlarmSnapshotWire]()
        let completed = expectation(description: "query completes")

        fixture.plugin.getScheduledAlarms { result in
            if case let .failure(error) = result { XCTFail("Query failed: \(error)") }
            snapshots = (try? result.get()) ?? []
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        let snapshot = try XCTUnwrap(snapshots.first { $0.id == fixture.alarmId })
        XCTAssertEqual(snapshot.snooze?.durationMillis, 300_000)
        XCTAssertEqual(snapshot.snooze?.maxCount, 3)
    }

    // MARK: - Snooze

    func testSnoozeCountRestartsOnlyForAWeeklyDelivery() throws {
        let fixture = try fixture()
        var recurring = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1, 3], maxCount: 2))
        recurring.snoozeCount = 2
        var oneShot = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 2))
        oneShot.snoozeCount = 2
        let id = fixture.alarmId

        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: recurring, deliveredIdentifier: "\(id)#1"), 0)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: recurring, deliveredIdentifier: "\(id)#3"), 0)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: recurring, deliveredIdentifier: "\(id)#5"), 2)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: recurring, deliveredIdentifier: String(id)), 2)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: recurring, deliveredIdentifier: nil), 2)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: oneShot, deliveredIdentifier: String(id)), 2)
        XCTAssertEqual(WarmAlarmDelegate.snoozeCountBeforeAction(for: oneShot, deliveredIdentifier: "\(id)#1"), 2)
    }

    func testSnoozeWithinTheLimitStoresTheNextCountAndRegistersAStopOnlyRing() throws {
        let fixture = try fixture()
        let schedule = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 1))
        WarmAlarmStore.shared.save(schedule)
        let content = fixture.delegate.makeContent(from: schedule)
        let done = expectation(description: "snooze completes")

        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: String(fixture.alarmId),
            content: content, deliveredAtMillis: 1_000
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        let stored = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.alarmId))
        XCTAssertEqual(stored.snoozeCount, 1)
        XCTAssertEqual(stored.snoozeMaxCount, 1)
        XCTAssertNotNil(stored.activeSnoozeUntilMillis)
        XCTAssertEqual(fixture.added.map(\.identifier), [String(fixture.alarmId)])
        XCTAssertEqual(registeredActionIdentifiers(for: fixture.added.map(\.content)), [["STOP"]])
        XCTAssertEqual(fixture.events.map(\.type), [.snoozed])
    }

    func testSnoozeOnTheSnoozedRingOfARecurringAlarmKeepsCounting() throws {
        let fixture = try fixture()
        var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1], maxCount: 2))
            .withActiveSnooze(untilMillis: 2_000, consumingOccurrenceMillis: 1_000)
        schedule.snoozeCount = 1
        WarmAlarmStore.shared.save(schedule)
        let done = expectation(description: "snoozed ring snooze completes")

        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: String(fixture.alarmId),
            content: fixture.delegate.makeContent(from: schedule), deliveredAtMillis: 2_000
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeCount, 2)
        XCTAssertEqual(registeredActionIdentifiers(for: fixture.added.map(\.content)), [["STOP"]])
    }

    func testSnoozeOnANewRecurringOccurrenceRestartsTheCount() throws {
        let fixture = try fixture()
        var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1], maxCount: 2))
            .withActiveSnooze(untilMillis: 3_000, consumingOccurrenceMillis: 1_000)
        schedule.snoozeMaxCount = 2
        schedule.snoozeCount = 2
        WarmAlarmStore.shared.save(schedule)
        let done = expectation(description: "new occurrence snooze completes")

        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: "\(fixture.alarmId)#1",
            content: fixture.delegate.makeContent(from: schedule.withSnoozeCount(0)), deliveredAtMillis: 5_000
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        let stored = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.alarmId))
        XCTAssertEqual(stored.snoozeCount, 1)
        XCTAssertEqual(stored.consumedOccurrenceMillis, 5_000)
        XCTAssertEqual(registeredActionIdentifiers(for: fixture.added.map(\.content)), [["STOP", "SNOOZE"]])
        XCTAssertEqual(fixture.events.map(\.type), [.snoozed])
    }

    func testSnoozePastTheLimitIsRefusedAndLeavesTheRingPlaying() throws {
        let fixture = try fixture()
        var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 1))
            .withActiveSnooze(untilMillis: 2_000, consumingOccurrenceMillis: 1_000)
        schedule.snoozeMaxCount = 1
        schedule.snoozeCount = 1
        WarmAlarmStore.shared.save(schedule)
        let before = try encoded(WarmAlarmStore.shared.load(id: fixture.alarmId))
        let identifier = String(fixture.alarmId)
        let content = fixture.delegate.makeContent(from: schedule)
        _ = fixture.delegate.handleForegroundDelivery(content: content, identifier: identifier, deliveredAtMillis: 2_000)
        let player = try XCTUnwrap(fixture.delegate.audioPlayer)
        fixture.add = { _, completion in
            XCTFail("A snooze past the limit must not register a request")
            completion(nil)
        }
        let done = expectation(description: "refused snooze completes")

        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: identifier,
            content: content, deliveredAtMillis: 2_000
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.alarmId)
        XCTAssertEqual(try encoded(WarmAlarmStore.shared.load(id: fixture.alarmId)), before)
        XCTAssertEqual(fixture.events.map(\.type), [.fired])
    }

    func testFailedLimitedSnoozeKeepsTheStoredCount() throws {
        let fixture = try fixture()
        var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 2))
            .withActiveSnooze(untilMillis: 2_000, consumingOccurrenceMillis: 1_000)
        schedule.snoozeMaxCount = 2
        schedule.snoozeCount = 1
        WarmAlarmStore.shared.save(schedule)
        let before = try encoded(WarmAlarmStore.shared.load(id: fixture.alarmId))
        var attempted = [UNNotificationRequest]()
        fixture.add = { request, completion in
            attempted.append(request)
            completion(NSError(domain: "snooze-limit-test", code: 1))
        }
        let done = expectation(description: "failed snooze completes")

        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: String(fixture.alarmId),
            content: fixture.delegate.makeContent(from: schedule), deliveredAtMillis: 2_000
        ) { done.fulfill() }

        wait(for: [done], timeout: 2)
        XCTAssertEqual(registeredActionIdentifiers(for: attempted.map(\.content)), [["STOP"]])
        XCTAssertEqual(try encoded(WarmAlarmStore.shared.load(id: fixture.alarmId)), before)
        XCTAssertEqual(fixture.events.map(\.type), [.failed])
    }

    // MARK: - Stop

    func testStoppingTheSnoozedRingResetsTheRecurringSnoozeCount() throws {
        let fixture = try fixture()
        let snoozeMillis = Int64(Date().timeIntervalSince1970 * 1_000) + 300_000
        var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1, 2, 3], maxCount: 2))
            .withActiveSnooze(untilMillis: snoozeMillis, consumingOccurrenceMillis: 1_000)
        schedule.snoozeMaxCount = 2
        schedule.snoozeCount = 1
        WarmAlarmStore.shared.save(schedule)
        let identifier = String(fixture.alarmId)
        let content = fixture.delegate.makeContent(from: schedule)
        let token = WarmAlarmDelegate.occurrenceToken(content: content, identifier: identifier, deliveredAtMillis: snoozeMillis)

        fixture.delegate.handleStop(
            alarmId: fixture.alarmId, deliveredIdentifier: identifier, content: content, occurrenceToken: token
        )

        let stored = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.alarmId))
        XCTAssertEqual(stored.snoozeCount, 0)
        XCTAssertEqual(stored.snoozeMaxCount, 2)
        XCTAssertEqual(stored.consumedOccurrenceMillis, snoozeMillis)
        XCTAssertEqual(fixture.events.map(\.type), [.stopped])
    }

    func testStoppingAWeeklyRingKeepsTheCountOnlyWhileAnEarlierSnoozeIsPending() throws {
        let fixture = try fixture()
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
        let identifier = "\(fixture.alarmId)#1"
        for (snoozeUntilMillis, expectedCount) in [(nowMillis + 300_000, Int64(1)), (nowMillis - 300_000, Int64(0))] {
            var schedule = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1], maxCount: 2))
                .withActiveSnooze(untilMillis: snoozeUntilMillis, consumingOccurrenceMillis: 1_000)
            schedule.snoozeMaxCount = 2
            schedule.snoozeCount = 1
            WarmAlarmStore.shared.save(schedule)
            let content = fixture.delegate.makeContent(from: schedule.withSnoozeCount(0))
            let token = WarmAlarmDelegate.occurrenceToken(content: content, identifier: identifier, deliveredAtMillis: 2_000)

            fixture.delegate.handleStop(
                alarmId: fixture.alarmId, deliveredIdentifier: identifier, content: content, occurrenceToken: token
            )

            let stored = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.alarmId))
            let message = "snooze until \(snoozeUntilMillis - nowMillis) ms from now"
            XCTAssertEqual(stored.snoozeCount, expectedCount, message)
            XCTAssertEqual(stored.snoozeMaxCount, 2, message)
            XCTAssertEqual(stored.consumedOccurrenceMillis, 2_000, message)
        }
    }

    // MARK: - Recovery

    func testRecoveryRebuildsTheSnoozedRingAtTheLimitAndKeepsSnoozeOnWeeklyRequests() throws {
        let fixture = try fixture()
        let nowMillis: Int64 = 1_900_000_000_000
        var recurring = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1, 3], maxCount: 1))
            .withActiveSnooze(untilMillis: nowMillis + 240_000)
        recurring.snoozeMaxCount = 1
        recurring.snoozeCount = 1
        let id = fixture.alarmId

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: recurring,
            identifiers: ["\(id)#1", "\(id)#3", String(id)],
            nowMillis: nowMillis,
            makeContent: fixture.delegate.makeContent(from:)
        )

        XCTAssertEqual(requests.map(\.identifier), ["\(id)#1", "\(id)#3", String(id)])
        XCTAssertEqual(
            registeredActionIdentifiers(for: requests.map(\.content)),
            [["STOP", "SNOOZE"], ["STOP", "SNOOZE"], ["STOP"]]
        )
    }

    // MARK: - Store

    func testSnoozeLimitAndCountSurviveStorageAndLegacyPayloadsDecodeWithNoLimit() throws {
        let fixture = try fixture()
        var limited = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 2))
        limited.snoozeCount = 1
        WarmAlarmStore.shared.save(limited)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeMaxCount, 2)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.alarmId)?.snoozeCount, 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(limited)) as? [String: Any])
        json.removeValue(forKey: "snoozeMaxCount")
        json.removeValue(forKey: "snoozeCount")

        let legacy = try JSONDecoder().decode(
            WarmAlarmScheduleData.self, from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertNil(legacy.snoozeMaxCount)
        XCTAssertEqual(legacy.snoozeCount, 0)
        XCTAssertTrue(legacy.offersSnooze)
    }

    func testFromWireCarriesSnoozeMaxCountAndStartsCountAtZero() throws {
        let fixture = try fixture()
        let limited = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: 3))
        let unlimited = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: nil))

        XCTAssertEqual(limited.snoozeMaxCount, 3)
        XCTAssertEqual(limited.snoozeCount, 0)
        XCTAssertNil(unlimited.snoozeMaxCount)
        XCTAssertEqual(unlimited.snoozeCount, 0)
    }

    func testOffersSnoozeComparesCountWithMaxCount() throws {
        let fixture = try fixture()
        let cases: [(maxCount: Int64?, count: Int64, offersSnooze: Bool)] = [
            (nil, 0, true), (nil, 9, true), (0, 0, false), (2, 1, true), (2, 2, false), (2, 3, false),
        ]
        for testCase in cases {
            var data = WarmAlarmScheduleData.from(wire: fixture.wire(maxCount: testCase.maxCount))
            data.snoozeCount = testCase.count
            XCTAssertEqual(
                data.offersSnooze,
                testCase.offersSnooze,
                "maxCount \(String(describing: testCase.maxCount)), count \(testCase.count)"
            )
        }
    }

    func testScheduleStateCopiesKeepSnoozeLimitAndCount() throws {
        let fixture = try fixture()
        var data = WarmAlarmScheduleData.from(wire: fixture.wire(recurrenceWeekdays: [1], maxCount: 2))
        data.snoozeCount = 1
        let copies = [
            data.withActiveSnooze(untilMillis: 1_000),
            data.withActiveSnooze(untilMillis: 1_000, consumingOccurrenceMillis: 500),
            data.withConsumedOccurrence(2_000),
            data.withRecurrenceTime(hour: 8, minute: 30),
        ]

        for copy in copies {
            XCTAssertEqual(copy.snoozeMaxCount, 2)
            XCTAssertEqual(copy.snoozeCount, 1)
        }
        XCTAssertEqual(data.withSnoozeCount(2).snoozeCount, 2)
        XCTAssertEqual(data.withSnoozeCount(2).snoozeMaxCount, 2)
        XCTAssertEqual(data.withSnoozeCount(0).snoozeCount, 0)
    }

    // MARK: - Helpers

    private func fixture() throws -> SnoozeLimitFixture {
        let fixture = try SnoozeLimitFixture()
        addTeardownBlock { try fixture.cleanUp() }
        return fixture
    }

    private func schedule(_ wire: WarmAlarmScheduleWire, with fixture: SnoozeLimitFixture) throws {
        let scheduled = expectation(description: "schedule completes")
        fixture.plugin.scheduleAlarm(schedule: wire) { result in
            if case let .failure(error) = result { XCTFail("Scheduling failed: \(error)") }
            scheduled.fulfill()
        }
        wait(for: [scheduled], timeout: 2)
    }

    private func encoded(_ schedule: WarmAlarmScheduleData?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(schedule)
    }

    private func registeredActionIdentifiers(for contents: [UNNotificationContent]) -> [[String]] {
        var registered = Set<UNNotificationCategory>()
        let done = expectation(description: "categories registered")
        WarmAlarmDelegate.registerCategories(for: contents, read: { $0([]) }, write: { registered = $0 }) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return contents.map { content in
            registered.first { $0.identifier == content.categoryIdentifier }?.actions.map(\.identifier) ?? []
        }
    }
}

// The fixture is driven serially by each XCTest; asynchronous callbacks are awaited before cleanup.
private final class SnoozeLimitFixture: @unchecked Sendable {
    let alarmId: Int64 = 7_171_001
    let directory: URL
    let audioPath: String
    var events = [WarmAlarmEventWire]()
    var pending = [UNNotificationRequest]()
    var added = [UNNotificationRequest]()
    var add: WarmAlarmPlugin.NotificationAdder
    var delegate: WarmAlarmDelegate!
    var plugin: WarmAlarmPlugin!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("audio.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 8_000)
        let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        try file.write(from: buffer)
        audioPath = audioURL.path
        add = { _, completion in completion(nil) }
        add = { [unowned self] request, completion in
            added.append(request)
            completion(nil)
        }
        let queue = WarmAlarmEventQueue(
            store: WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(
                fileURL: directory.appendingPathComponent("events.json")
            )),
            emit: { [weak self] event, completion in
                self?.events.append(event)
                completion(true)
            }
        )
        delegate = WarmAlarmDelegate(
            eventsApi: WarmAlarmEventsApi(binaryMessenger: SnoozeLimitTestMessenger()),
            eventQueue: queue,
            pendingNotificationReader: { [weak self] completion in completion(self?.pending ?? []) },
            notificationAdder: { [weak self] request, completion in self?.add(request, completion) },
            categoryRegistrar: { _, completion in completion() }
        )
        plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationAdder: { [weak self] request, completion in self?.add(request, completion) },
            authorizationStatusReader: { $0(.authorized) },
            pendingNotificationReader: { [weak self] completion in completion(self?.pending ?? []) },
            pendingNotificationRemover: { [weak self] ids in self?.pending.removeAll { ids.contains($0.identifier) } },
            deliveredNotificationRemover: { _ in }
        )
        WarmAlarmStore.shared.remove(id: alarmId)
    }

    func wire(recurrenceWeekdays: [Int64]? = nil, maxCount: Int64?) -> WarmAlarmScheduleWire {
        WarmAlarmScheduleWire(
            id: alarmId, scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Snooze limit", body: "Alarm", stopActionTitle: "Dismiss", snoozeActionTitle: "Later",
                keepNotificationAfterAlarmEnds: true
            ),
            audio: WarmAlarmAudioWire(filePath: audioPath, loop: true, volume: 0, vibrate: false, volumeEnforced: false),
            recurrence: recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) },
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000, maxCount: maxCount)
        )
    }

    func cleanUp() throws {
        delegate.stopAllIfPlaying()
        WarmAlarmStore.shared.remove(id: alarmId)
        try FileManager.default.removeItem(at: directory)
    }
}

private final class SnoozeLimitTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
    func setMessageHandlerOnChannel(
        _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
