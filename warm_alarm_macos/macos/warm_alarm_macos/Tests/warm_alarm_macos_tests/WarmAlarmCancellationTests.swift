import AVFoundation
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmCancellationTests: XCTestCase {
    func testCancelActiveAlarmStopsPlaybackBeforeCompletion() throws {
        let (plugin, delegate, player, alarmID) = try playingAlarmFixture()
        let completed = expectation(description: "active alarm cancelled")

        plugin.cancelAlarm(id: alarmID) { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertFalse(player.isPlaying)
            XCTAssertNil(delegate.audioPlayer)
            XCTAssertNil(delegate.currentlyPlayingAlarmId)
            plugin.isRinging(alarmId: alarmID) { XCTAssertEqual(try? $0.get(), false) }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        withExtendedLifetime(plugin) {}
    }

    func testCancelDifferentAlarmPreservesActivePlayback() throws {
        let (plugin, delegate, player, alarmID) = try playingAlarmFixture()
        let completed = expectation(description: "different alarm cancelled")

        plugin.cancelAlarm(id: alarmID + 1) { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(delegate.currentlyPlayingAlarmId, alarmID)
            plugin.isRinging(alarmId: alarmID) { XCTAssertEqual(try? $0.get(), true) }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        withExtendedLifetime(plugin) {}
    }

    func testCancelAllStopsPlaybackBeforeCompletion() throws {
        let (plugin, delegate, player, _) = try playingAlarmFixture()
        let completed = expectation(description: "all alarms cancelled")

        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertFalse(player.isPlaying)
            XCTAssertNil(delegate.audioPlayer)
            XCTAssertNil(delegate.currentlyPlayingAlarmId)
            plugin.isRinging(alarmId: nil) { XCTAssertEqual(try? $0.get(), false) }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        withExtendedLifetime(plugin) {}
    }

    func testCancelAllStopsPlaybackWithoutStoredSchedule() throws {
        let (plugin, delegate, player, alarmID) = try playingAlarmFixture()
        WarmAlarmStore.shared.remove(id: alarmID)
        let completed = expectation(description: "unpersisted playback cancelled")

        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertFalse(player.isPlaying)
            XCTAssertNil(delegate.currentlyPlayingAlarmId)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        withExtendedLifetime(plugin) {}
    }

    func testCancelAllPreservesHostNotificationsAndRemovesOwnedOrphans() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let delegate = makeDelegate()
        let schedule = makeSchedule()
        let content = delegate.makeContent(from: schedule)
        var pending = ["7760001", "7760001#1", "7760001#5", "orphan-alarm"].map {
            UNNotificationRequest(identifier: $0, content: content, trigger: nil)
        }
        let hostIDs = ["host-reminder", "42", "warm_alarm_host_notice", "warm_alarm_kill_warning_notif-copy"]
        let hostContent = UNMutableNotificationContent()
        hostContent.categoryIdentifier = "HOST_NOTIFICATION"
        hostContent.userInfo = ["alarmId": "7760001"]
        pending += hostIDs.map { UNNotificationRequest(identifier: $0, content: hostContent, trigger: nil) }
        pending.append(UNNotificationRequest(
            identifier: "warm_alarm_kill_warning_notif", content: UNMutableNotificationContent(), trigger: nil
        ))
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { $0(pending) },
            pendingNotificationRemover: { identifiers in pending.removeAll { identifiers.contains($0.identifier) } }
        )
        let completed = expectation(description: "scoped cancellation completes")

        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(Set(pending.map(\.identifier)), Set(hostIDs))
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
        withExtendedLifetime(plugin) {}
    }

    func testCancelAllSuppressesForegroundDeliveryWhileWaitingForPendingRead() throws {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let schedule = makeSchedule()
        WarmAlarmStore.shared.save(schedule)
        let delegate = makeDelegate()
        let content = delegate.makeContent(from: schedule)
        let readStarted = expectation(description: "pending read starts")
        let secondRead = expectation(description: "later cancellation must wait")
        secondRead.isInverted = true
        var didReleaseRead = false
        var readCompletion: (([UNNotificationRequest]) -> Void)?
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { completion in
                if readCompletion == nil {
                    readCompletion = completion
                    readStarted.fulfill()
                } else {
                    if !didReleaseRead { secondRead.fulfill() }
                    completion([])
                }
            },
            pendingNotificationRemover: { _ in }
        )
        var didComplete = false
        let completed = expectation(description: "cancellation completes after read")
        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            didComplete = true
            completed.fulfill()
        }
        wait(for: [readStarted], timeout: 2)
        let secondCompleted = expectation(description: "later cancellation completes")
        plugin.cancelAllAlarms { _ in secondCompleted.fulfill() }
        wait(for: [secondRead], timeout: 0.05)

        XCTAssertFalse(didComplete)
        XCTAssertNil(WarmAlarmStore.shared.load(id: schedule.id))
        XCTAssertTrue(delegate.handleForegroundDelivery(content: content).isEmpty)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        didReleaseRead = true
        try XCTUnwrap(readCompletion)([])

        wait(for: [completed, secondCompleted], timeout: 2)
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
        withExtendedLifetime(plugin) {}
    }

    private func makeDelegate() -> WarmAlarmDelegate {
        WarmAlarmDelegate(eventsApi: WarmAlarmEventsApi(binaryMessenger: CancellationTestMessenger()))
    }

    private func playingAlarmFixture() throws -> (WarmAlarmPlugin, WarmAlarmDelegate, AVAudioPlayer, Int64) {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("silence.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 8_000)
        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            try file.write(from: buffer)
        }
        let eventQueue = WarmAlarmEventQueue(
            store: WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(
                fileURL: directory.appendingPathComponent("events.json")
            )),
            emit: { _, completion in completion(true) }
        )
        let delegate = WarmAlarmDelegate(
            eventsApi: WarmAlarmEventsApi(binaryMessenger: CancellationTestMessenger()),
            eventQueue: eventQueue
        )
        let schedule = WarmAlarmScheduleData.from(wire: WarmAlarmScheduleWire(
            id: 7_730_001,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Playback cancellation", body: "Alarm", keepNotificationAfterAlarmEnds: true
            ),
            audio: WarmAlarmAudioWire(
                filePath: fileURL.path, loop: true, volume: 0, vibrate: false, volumeEnforced: false
            )
        ))
        addTeardownBlock {
            WarmAlarmStore.shared.save(schedule)
            delegate.handleStop(alarmId: schedule.id)
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
            try FileManager.default.removeItem(at: directory)
        }
        WarmAlarmStore.shared.save(schedule)
        _ = delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule))
        let player = try XCTUnwrap(delegate.audioPlayer)
        XCTAssertTrue(player.isPlaying, "The regression fixture must start real looping playback")
        XCTAssertEqual(delegate.currentlyPlayingAlarmId, schedule.id)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { $0([]) },
            pendingNotificationRemover: { _ in },
            deliveredNotificationRemover: { _ in }
        )
        return (plugin, delegate, player, schedule.id)
    }

    private func makeSchedule() -> WarmAlarmScheduleData {
        .from(wire: WarmAlarmScheduleWire(
            id: 7_760_001,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Cancellation", body: "Alarm", keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: false, vibrate: false, volumeEnforced: false)
        ))
    }
}

private final class CancellationTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
