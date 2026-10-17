import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmReplacementTests: XCTestCase {
    func testFirstRegistrationFailureRestoresPreviousAlarm() throws {
        try assertReplacementFailure(failureIndex: 1)
    }

    func testPartialRegistrationFailureRestoresPreviousAlarm() throws {
        try assertReplacementFailure(failureIndex: 2)
    }

    func testPartialFailureRestoresRequestsWithOverlappingIdentifiers() throws {
        try assertReplacementFailure(failureIndex: 2, weekdays: [1, 5])
    }

    func testOneShotFailureRestoresPreviousSnoozeAndRecurrence() throws {
        try assertReplacementFailure(failureIndex: 1, weekdays: nil)
    }

    func testRollbackFailureStillAttemptsEveryPreviousRequest() throws {
        let fixture = try makeFixture()
        let previous = try encoded(fixture.previous)
        var attempts = [String]()
        fixture.add = { [unowned fixture] request, callback in
            attempts.append(request.identifier)
            if request.content.title == "Replacement" {
                callback(self.failure("replacement rejected"))
            } else if request.identifier == "7740001#1" {
                callback(self.failure("restoration rejected"))
            } else {
                fixture.install(request)
                callback(nil)
            }
        }
        let completed = expectation(description: "rollback failure returned")
        fixture.plugin.scheduleAlarm(schedule: fixture.replacement) { result in
            guard case let .failure(error) = result, let error = error as? PigeonError else {
                XCTFail("Expected explicit rollback failure")
                completed.fulfill()
                return
            }
            XCTAssertEqual(error.code, "scheduling-rollback-failed")
            XCTAssertTrue(error.message?.contains("replacement rejected") == true)
            XCTAssertTrue(error.message?.contains("restoration rejected") == true)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(attempts, ["7740001#2", "7740001#1", "7740001#5", "7740001"])
        XCTAssertEqual(try encoded(WarmAlarmStore.shared.load(id: fixture.previous.id)), previous)
        XCTAssertEqual(Set(fixture.pending.map(\.identifier)), ["7740001#5", "7740001", "host-reminder"])
        XCTAssertEqual(WarmAlarmRecurrence.missingIdentifiers(
            alarmId: fixture.previous.id, weekdays: fixture.previous.recurrenceWeekdays,
            activeSnoozeUntilMillis: fixture.previous.activeSnoozeUntilMillis,
            nowMillis: 1_800_000_000_000,
            pendingIdentifiers: Set(fixture.pending.map(\.identifier))
        ), ["7740001#1"])
    }

    func testFailedFirstScheduleRemovesPartialRequestsAndStore() throws {
        let fixture = try makeFixture()
        WarmAlarmStore.shared.remove(id: fixture.previous.id)
        fixture.pending.removeAll { $0.identifier != "host-reminder" }
        var count = 0
        fixture.add = { [unowned fixture] request, callback in
            count += 1
            if count == 2 { callback(self.failure("registration rejected")) } else {
                fixture.install(request)
                callback(nil)
            }
        }
        let completed = expectation(description: "first schedule failed")
        fixture.plugin.scheduleAlarm(schedule: fixture.replacement) { result in
            if case .success = result { XCTFail("Registration failure must not return success") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.previous.id))
        XCTAssertEqual(fixture.pending.map(\.identifier), ["host-reminder"])
        XCTAssertEqual(fixture.events.map(\.type), [.failed])
    }

    func testSuccessfulReplacementRemovesPreviousRecurrenceAndSnooze() throws {
        let fixture = try makeFixture()
        let completed = expectation(description: "replacement succeeded")
        fixture.plugin.scheduleAlarm(schedule: fixture.replacement) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case let .success(value) = result else {
                XCTFail("Expected successful replacement")
                completed.fulfill()
                return
            }
            XCTAssertNil(value.warning)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(Set(fixture.pending.map(\.identifier)), ["7740001#2", "7740001#4", "host-reminder"])
        let saved = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.previous.id))
        XCTAssertEqual(saved.notificationTitle, "Replacement")
        XCTAssertNotEqual(saved.occurrenceSeriesToken, fixture.previous.occurrenceSeriesToken)
        XCTAssertEqual(fixture.events.map(\.type), [.scheduled])
    }

    func testCancellationWaitsUntilRollbackFinishes() throws {
        let fixture = try makeFixture()
        let restoreStarted = expectation(description: "restoration started")
        var restoreCompletion: (() -> Void)?
        fixture.add = { [unowned fixture] request, callback in
            if request.content.title == "Replacement" {
                callback(self.failure("registration rejected"))
            } else if restoreCompletion == nil {
                restoreCompletion = { [unowned fixture] in
                    fixture.install(request)
                    callback(nil)
                }
                restoreStarted.fulfill()
            } else {
                fixture.install(request)
                callback(nil)
            }
        }
        let replaced = expectation(description: "replacement replied")
        var replyCount = 0
        fixture.plugin.scheduleAlarm(schedule: fixture.replacement) { result in
            XCTAssertTrue(Thread.isMainThread)
            if case .success = result { XCTFail("Expected registration failure") }
            replyCount += 1
            replaced.fulfill()
        }
        wait(for: [restoreStarted], timeout: 2)
        let cancelled = expectation(description: "queued cancellation replied")
        let earlyCancellation = expectation(description: "cancellation must wait for restoration")
        earlyCancellation.isInverted = true
        var released = false
        fixture.plugin.cancelAlarm(id: fixture.previous.id) { result in
            if !released { earlyCancellation.fulfill() }
            if case .failure = result { XCTFail("Cancellation failed") }
            XCTAssertEqual(replyCount, 1, "Cancellation must follow the rollback reply")
            cancelled.fulfill()
        }
        wait(for: [earlyCancellation], timeout: 0.05)
        XCTAssertEqual(replyCount, 0)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.previous.id)?.notificationTitle, "Previous")
        released = true
        try XCTUnwrap(restoreCompletion)()
        wait(for: [replaced, cancelled], timeout: 2)
        XCTAssertEqual(replyCount, 1)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.previous.id))
        XCTAssertEqual(fixture.pending.map(\.identifier), ["host-reminder"])
    }

    private func assertReplacementFailure(failureIndex: Int, weekdays: [Int64]? = [2, 4]) throws {
        let fixture = try makeFixture()
        fixture.replacement.recurrence = weekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) }
        let previous = try encoded(fixture.previous)
        let requests = fixture.pending
        var replacementCount = 0
        fixture.add = { [unowned fixture] request, callback in
            if request.content.title == "Replacement" {
                replacementCount += 1
                if replacementCount == failureIndex {
                    callback(self.failure("registration rejected"))
                    return
                }
            } else {
                XCTAssertFalse(fixture.pending.contains { $0.content.title == "Replacement" })
                XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.previous.id)?.occurrenceSeriesToken,
                               fixture.previous.occurrenceSeriesToken)
            }
            fixture.install(request)
            callback(nil)
        }
        let completed = expectation(description: "replacement failed after restoration")
        fixture.plugin.scheduleAlarm(schedule: fixture.replacement) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case let .failure(error) = result, let error = error as? PigeonError else {
                XCTFail("Registration failure must return an error, not success with a warning")
                completed.fulfill()
                return
            }
            XCTAssertEqual(error.code, "scheduling-failed")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        XCTAssertEqual(try encoded(WarmAlarmStore.shared.load(id: fixture.previous.id)), previous)
        XCTAssertEqual(fixture.pending.count, requests.count)
        for request in requests {
            XCTAssertTrue(fixture.pending.contains { $0 === request }, "Restore the exact content and trigger")
        }
        XCTAssertEqual(fixture.events.map(\.type), [.failed])
    }

    private func makeFixture() throws -> ReplacementFixture {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = ReplacementFixture(directory: directory)
        addTeardownBlock {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
            try FileManager.default.removeItem(at: directory)
        }
        return fixture
    }

    private func encoded(_ schedule: WarmAlarmScheduleData?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(schedule)
    }

    private func failure(_ message: String) -> Error {
        NSError(domain: "ReplacementTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class ReplacementFixture {
    var pending = [UNNotificationRequest]()
    var events = [WarmAlarmEventWire]()
    var add: WarmAlarmPlugin.NotificationAdder?
    var plugin: WarmAlarmPlugin!
    let previous: WarmAlarmScheduleData
    var replacement: WarmAlarmScheduleWire

    init(directory: URL) {
        let schedule = WarmAlarmScheduleWire(
            id: 7_740_001, scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(title: "Previous", body: "Previous body", keepNotificationAfterAlarmEnds: true),
            audio: WarmAlarmAudioWire(loop: true, volume: 0, vibrate: false, volumeEnforced: false),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [1, 5]),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000), payload: "previous payload"
        )
        previous = WarmAlarmScheduleData.from(wire: schedule).withActiveSnooze(untilMillis: 1_900_000_300_000)
        replacement = WarmAlarmScheduleWire(
            id: schedule.id, scheduledAtMillis: 1_900_001_000_000,
            notification: WarmAlarmNotificationWire(title: "Replacement", body: "New body", keepNotificationAfterAlarmEnds: false),
            audio: schedule.audio, recurrence: WarmAlarmRecurrenceWire(weekdays: [2, 4]), payload: "replacement payload"
        )
        let queue = WarmAlarmEventQueue(
            store: WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(
                fileURL: directory.appendingPathComponent("events.json")
            )),
            emit: { [weak self] event, callback in
                self?.events.append(event)
                callback(true)
            }
        )
        let delegate = WarmAlarmDelegate(
            eventsApi: WarmAlarmEventsApi(binaryMessenger: ReplacementTestMessenger()), eventQueue: queue,
            categoryRegistrar: { _, completion in completion() }
        )
        let content = delegate.makeContent(from: previous)
        pending = ([1, 5] as [Int]).map {
            UNNotificationRequest(identifier: "7740001#\($0)", content: content, trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 8, minute: 15, weekday: $0), repeats: true
            ))
        }
        pending.append(UNNotificationRequest(identifier: "7740001", content: content, trigger:
            UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)))
        let host = UNMutableNotificationContent()
        host.title = "Host"
        host.userInfo = ["alarmId": "7740001"]
        pending.append(UNNotificationRequest(identifier: "host-reminder", content: host, trigger: nil))
        WarmAlarmStore.shared.save(previous)
        plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationAdder: { [unowned self] request, callback in
                if let add { add(request, callback) } else {
                    install(request)
                    callback(nil)
                }
            },
            authorizationStatusReader: { $0(.authorized) },
            pendingNotificationReader: { [unowned self] in $0(pending) },
            pendingNotificationRemover: { [unowned self] ids in pending.removeAll { ids.contains($0.identifier) } },
            deliveredNotificationRemover: { _ in }
        )
    }

    func install(_ request: UNNotificationRequest) {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }
}

private final class ReplacementTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
