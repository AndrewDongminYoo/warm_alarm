import AVFoundation
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmActionTests: XCTestCase {
    func testStopPreservesAnotherAlarmsPlayback() throws {
        let fixture = try fixture()
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.delegate.makeContent(from: fixture.other))
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.other.id)
        fixture.delegate.handleStop(alarmId: fixture.schedule.id, content: fixture.content)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.other.id)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.schedule.id))
        XCTAssertEqual(fixture.events.map(\.type), [.fired, .stopped])
    }

    func testSnoozePreservesAnotherAlarmsPlayback() throws {
        let fixture = try fixture()
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.delegate.makeContent(from: fixture.other))
        let done = expectation(description: "snooze completed")
        fixture.delegate.handleSnooze(alarmId: fixture.schedule.id, content: fixture.content) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.other.id)
        XCTAssertEqual(fixture.events.map(\.type), [.fired, .snoozed])
    }

    func testOldStopDoesNotRemoveReplacement() throws {
        let fixture = try fixture()
        let replacement = WarmAlarmScheduleData.from(wire: fixture.wire)
        WarmAlarmStore.shared.save(replacement)
        fixture.delegate.handleStop(alarmId: fixture.schedule.id, content: fixture.content)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: replacement.id)?.occurrenceSeriesToken,
                       replacement.occurrenceSeriesToken)
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testOldSnoozeDoesNotChangeReplacement() throws {
        let fixture = try fixture()
        let replacement = WarmAlarmScheduleData.from(wire: fixture.wire)
        WarmAlarmStore.shared.save(replacement)
        fixture.add = { _, _ in XCTFail("Old notification must not register a snooze") }
        let done = expectation(description: "stale snooze completed")
        fixture.delegate.handleSnooze(alarmId: fixture.schedule.id, content: fixture.content) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: replacement.id)?.activeSnoozeUntilMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: replacement.id)?.occurrenceSeriesToken,
                       replacement.occurrenceSeriesToken)
        XCTAssertTrue(fixture.events.isEmpty)
    }

    func testSnoozeCommitsOnlyAfterRegistrationSucceeds() throws {
        let fixture = try fixture()
        var register: ((Error?) -> Void)?
        let entered = expectation(description: "registration entered")
        fixture.add = { _, completion in register = completion; entered.fulfill() }
        var completed = false
        let token = WarmAlarmDelegate.occurrenceToken(
            content: fixture.content, identifier: String(fixture.schedule.id), deliveredAtMillis: 1_000
        )
        fixture.delegate.handleSnooze(
            alarmId: fixture.schedule.id, content: fixture.content, occurrenceToken: token
        ) { completed = true }
        wait(for: [entered], timeout: 2)
        XCTAssertNotNil(register)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.schedule.id)?.activeSnoozeUntilMillis)
        XCTAssertFalse(completed)
        XCTAssertTrue(fixture.events.isEmpty)
        try XCTUnwrap(register)(nil)
        XCTAssertTrue(completed)
        XCTAssertNotNil(WarmAlarmStore.shared.load(id: fixture.schedule.id)?.activeSnoozeUntilMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: fixture.schedule.id)?.snoozedOccurrenceMillis, 1_000)
        XCTAssertEqual(fixture.events.map(\.type), [.snoozed])
    }

    func testFailedSnoozePreservesPreviousStateAndReportsFailure() throws {
        let fixture = try fixture()
        let previous = fixture.schedule.withActiveSnooze(untilMillis: 1_900_000_060_000, consumingOccurrenceMillis: 500)
        WarmAlarmStore.shared.save(previous)
        fixture.add = { _, completion in
            completion(NSError(domain: "snooze-test", code: 1))
        }
        let done = expectation(description: "failed snooze completed")
        fixture.delegate.handleSnooze(alarmId: fixture.schedule.id, content: fixture.content) { done.fulfill() }
        wait(for: [done], timeout: 2)
        let after = try XCTUnwrap(WarmAlarmStore.shared.load(id: fixture.schedule.id))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(after), try encoder.encode(previous))
        XCTAssertEqual(fixture.events.map(\.type), [.failed])
        XCTAssertEqual(fixture.events.first?.failure?.code, .schedulingFailed)
    }

    func testOlderOccurrenceCannotStopCurrentPlaybackOfSameAlarm() throws {
        let fixture = try fixture()
        let identifier = String(fixture.schedule.id)
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.content, identifier: identifier, deliveredAtMillis: 2_000)
        let player = try XCTUnwrap(fixture.delegate.audioPlayer)
        let oldToken = WarmAlarmDelegate.occurrenceToken(content: fixture.content, identifier: identifier, deliveredAtMillis: 1_000)
        fixture.delegate.handleStop(alarmId: fixture.schedule.id, content: fixture.content, occurrenceToken: oldToken)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.schedule.id)
        XCTAssertNotNil(WarmAlarmStore.shared.load(id: fixture.schedule.id))
        XCTAssertEqual(fixture.events.map(\.type), [.fired])
    }

    func testOlderSnoozeCannotStopCurrentPlaybackOfSameAlarm() throws {
        let fixture = try fixture()
        let identifier = String(fixture.schedule.id)
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.content, identifier: identifier, deliveredAtMillis: 2_000)
        let player = try XCTUnwrap(fixture.delegate.audioPlayer)
        let oldToken = WarmAlarmDelegate.occurrenceToken(content: fixture.content, identifier: identifier, deliveredAtMillis: 1_000)
        let done = expectation(description: "older snooze completed")
        fixture.delegate.handleSnooze(alarmId: fixture.schedule.id, content: fixture.content, occurrenceToken: oldToken) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.schedule.id)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.schedule.id)?.activeSnoozeUntilMillis)
        XCTAssertEqual(fixture.events.map(\.type), [.fired])
    }

    func testOldResponsesCannotChangePersistedSnooze() throws {
        let fixture = try fixture()
        let snoozed = fixture.schedule.withActiveSnooze(untilMillis: 2_000)
        for action in [WarmAlarmDelegate.stopActionIdentifier, WarmAlarmDelegate.snoozeActionIdentifier,
                       UNNotificationDefaultActionIdentifier] {
            WarmAlarmStore.shared.save(snoozed)
            fixture.events.removeAll()
            let done = expectation(description: "old response ignored")
            fixture.delegate.handleNotificationResponse(
                actionIdentifier: action, deliveredIdentifier: String(snoozed.id),
                content: fixture.content, deliveredAtMillis: 1_000
            ) { done.fulfill() }
            wait(for: [done], timeout: 2)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: snoozed.id)?.activeSnoozeUntilMillis, 2_000)
            XCTAssertTrue(fixture.events.isEmpty)
        }
    }

    func testRetainedRepeatingResponseCannotConsumeActiveSnooze() throws {
        let fixture = try fixture()
        var wire = fixture.wire
        wire.recurrence = WarmAlarmRecurrenceWire(weekdays: [1])
        wire.snooze = WarmAlarmSnoozeWire(durationMillis: 1_000)
        let repeating = WarmAlarmScheduleData.from(wire: wire).withActiveSnooze(untilMillis: 3_000, consumingOccurrenceMillis: 1_000)
        for action in [WarmAlarmDelegate.stopActionIdentifier, WarmAlarmDelegate.snoozeActionIdentifier,
                       UNNotificationDefaultActionIdentifier] {
            WarmAlarmStore.shared.save(repeating)
            fixture.events.removeAll()
            let done = expectation(description: "retained repeating response ignored")
            fixture.delegate.handleNotificationResponse(
                actionIdentifier: action, deliveredIdentifier: "\(repeating.id)#1",
                content: fixture.delegate.makeContent(from: repeating), deliveredAtMillis: 1_000
            ) { done.fulfill() }
            wait(for: [done], timeout: 2)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: repeating.id)?.activeSnoozeUntilMillis, 3_000)
            XCTAssertTrue(fixture.events.isEmpty)
        }
    }

    func testRepeatingOccurrenceBeforeSnoozeDeadlineStillFires() throws {
        let fixture = try fixture()
        var wire = fixture.wire
        wire.recurrence = WarmAlarmRecurrenceWire(weekdays: [1])
        wire.snooze = WarmAlarmSnoozeWire(durationMillis: 1_000)
        let repeating = WarmAlarmScheduleData.from(wire: wire).withActiveSnooze(untilMillis: 3_000, consumingOccurrenceMillis: 1_000)
        WarmAlarmStore.shared.save(repeating)
        let options = fixture.delegate.handleForegroundDelivery(
            content: fixture.delegate.makeContent(from: repeating),
            identifier: "\(repeating.id)#1", deliveredAtMillis: 1_500
        )
        XCTAssertEqual(options, [.alert])
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, repeating.id)
        XCTAssertEqual(fixture.events.map(\.type), [.fired])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: repeating.id)?.activeSnoozeUntilMillis, 3_000)
        let done = expectation(description: "later repeating occurrence can snooze")
        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier, deliveredIdentifier: "\(repeating.id)#1",
            content: fixture.delegate.makeContent(from: repeating), deliveredAtMillis: 1_500
        ) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: repeating.id)?.snoozedOccurrenceMillis, 1_500)
        XCTAssertEqual(fixture.events.map(\.type), [.fired, .snoozed])
    }

    func testConsumedOccurrenceSurvivesStorageAndLegacyPayloadsStillDecode() throws {
        let fixture = try fixture()
        let snoozed = fixture.schedule.withActiveSnooze(untilMillis: 3_000, consumingOccurrenceMillis: 1_000)
            .withRecurrenceTime(hour: 7, minute: 0)
        WarmAlarmStore.shared.save(snoozed)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: snoozed.id)?.snoozedOccurrenceMillis, 1_000)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snoozed)) as? [String: Any])
        legacy.removeValue(forKey: "snoozedOccurrenceMillis")
        let decoded = try JSONDecoder().decode(
            WarmAlarmScheduleData.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(decoded.snoozedOccurrenceMillis)
        XCTAssertEqual(decoded.activeSnoozeUntilMillis, 3_000)
    }

    func testMatchingOccurrenceStopsItsPlayer() throws {
        let fixture = try fixture()
        let identifier = String(fixture.schedule.id)
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.content, identifier: identifier, deliveredAtMillis: 2_000)
        let player = try XCTUnwrap(fixture.delegate.audioPlayer)
        let token = WarmAlarmDelegate.occurrenceToken(content: fixture.content, identifier: identifier, deliveredAtMillis: 2_000)
        fixture.delegate.handleStop(alarmId: fixture.schedule.id, content: fixture.content, occurrenceToken: token)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(fixture.delegate.currentlyPlayingAlarmId)
    }

    func testStaleDefaultTapPreservesReplacementAndOtherPlayback() throws {
        let fixture = try fixture()
        _ = fixture.delegate.handleForegroundDelivery(content: fixture.delegate.makeContent(from: fixture.other))
        let replacement = WarmAlarmScheduleData.from(wire: fixture.wire)
        WarmAlarmStore.shared.save(replacement)
        let done = expectation(description: "stale tap completed")
        fixture.delegate.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            deliveredIdentifier: String(fixture.schedule.id), content: fixture.content, deliveredAtMillis: 1_000
        ) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fixture.delegate.currentlyPlayingAlarmId, fixture.other.id)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: replacement.id)?.occurrenceSeriesToken, replacement.occurrenceSeriesToken)
        XCTAssertEqual(fixture.events.map(\.type), [.fired])
    }

    func testCancellationWaitsForSnoozeRegistration() throws {
        let fixture = try fixture()
        let entered = expectation(description: "snooze registration entered")
        var register: ((Error?) -> Void)?
        fixture.add = { _, completion in register = completion; entered.fulfill() }
        let snoozed = expectation(description: "snooze response completed")
        fixture.delegate.handleNotificationResponse(
            actionIdentifier: WarmAlarmDelegate.snoozeActionIdentifier,
            deliveredIdentifier: String(fixture.schedule.id), content: fixture.content, deliveredAtMillis: 1_000
        ) { snoozed.fulfill() }
        wait(for: [entered], timeout: 2)
        let plugin = WarmAlarmPlugin(
            delegate: fixture.delegate,
            pendingNotificationReader: { $0([]) },
            pendingNotificationRemover: { _ in }, deliveredNotificationRemover: { _ in }
        )
        let early = expectation(description: "cancellation cannot overtake snooze")
        early.isInverted = true
        let cancelled = expectation(description: "cancellation completed")
        var released = false
        plugin.cancelAlarm(id: fixture.schedule.id) { result in
            if !released { early.fulfill() }
            if case .failure = result { XCTFail("Cancellation failed") }
            cancelled.fulfill()
        }
        wait(for: [early], timeout: 0.05)
        released = true
        try XCTUnwrap(register)(nil)
        wait(for: [snoozed, cancelled], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.schedule.id))
        withExtendedLifetime(plugin) {}
    }

    func testFailedSnoozeRestoresPreviousPendingRequest() throws {
        let fixture = try fixture()
        let previous = UNNotificationRequest(
            identifier: String(fixture.schedule.id), content: fixture.content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        )
        fixture.pending = [previous]
        var attempts = [UNNotificationRequest]()
        fixture.add = { request, completion in
            attempts.append(request)
            if attempts.count == 1 {
                fixture.pending = []
                completion(NSError(domain: "snooze-test", code: 1))
            } else {
                fixture.pending = [request]
                completion(nil)
            }
        }
        let done = expectation(description: "rollback completed")
        fixture.delegate.handleSnooze(alarmId: fixture.schedule.id, content: fixture.content) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertTrue(fixture.pending.first === previous)
        XCTAssertNil(WarmAlarmStore.shared.load(id: fixture.schedule.id)?.activeSnoozeUntilMillis)
        XCTAssertEqual(fixture.events.map(\.type), [.failed])
    }

    private func fixture() throws -> ActionFixture {
        let fixture = try ActionFixture()
        addTeardownBlock { try fixture.cleanUp() }
        return fixture
    }
}

// The fixture is driven serially by each XCTest; asynchronous callbacks are awaited before cleanup.
private final class ActionFixture: @unchecked Sendable {
    let directory: URL
    let wire: WarmAlarmScheduleWire
    let schedule: WarmAlarmScheduleData
    let other: WarmAlarmScheduleData
    var events = [WarmAlarmEventWire]()
    var pending = [UNNotificationRequest]()
    var add: WarmAlarmPlugin.NotificationAdder = { _, completion in completion(nil) }
    var delegate: WarmAlarmDelegate!
    var content: UNNotificationContent { delegate.makeContent(from: schedule) }

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
        wire = WarmAlarmScheduleWire(
            id: 7_780_001, scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Action", body: "Alarm", stopActionTitle: "Dismiss", snoozeActionTitle: "Later",
                keepNotificationAfterAlarmEnds: true
            ),
            audio: WarmAlarmAudioWire(filePath: audioURL.path, loop: true, volume: 0, vibrate: false, volumeEnforced: false)
        )
        schedule = WarmAlarmScheduleData.from(wire: wire)
        var otherWire = wire
        otherWire.id += 1
        other = WarmAlarmScheduleData.from(wire: otherWire)
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
            eventsApi: WarmAlarmEventsApi(binaryMessenger: ActionTestMessenger()),
            eventQueue: queue,
            pendingNotificationReader: { [weak self] completion in completion(self?.pending ?? []) },
            notificationAdder: { [weak self] request, completion in self?.add(request, completion) }
        )
        WarmAlarmStore.shared.save(schedule)
        WarmAlarmStore.shared.save(other)
    }

    func cleanUp() throws {
        delegate.stopAllIfPlaying()
        WarmAlarmStore.shared.remove(id: schedule.id)
        WarmAlarmStore.shared.remove(id: other.id)
        try FileManager.default.removeItem(at: directory)
    }
}

private final class ActionTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { callback?(nil) }
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
