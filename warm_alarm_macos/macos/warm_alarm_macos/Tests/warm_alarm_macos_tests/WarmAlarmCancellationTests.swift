import AVFoundation
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmCancellationTests: XCTestCase {
    func testCancelAlarmWaitsForConcurrentForegroundStartup() throws {
        try assertCancellationWaitsForForegroundStartup(cancelAll: false)
    }

    func testCancelAllWaitsForConcurrentForegroundStartup() throws {
        try assertCancellationWaitsForForegroundStartup(cancelAll: true)
    }

    func testCancelAlarmBeforeRevalidationSuppressesForegroundDelivery() throws {
        try assertCancellationSuppressesDeliveryBeforeRevalidation(cancelAll: false)
    }

    func testCancelAllBeforeRevalidationSuppressesForegroundDelivery() throws {
        try assertCancellationSuppressesDeliveryBeforeRevalidation(cancelAll: true)
    }

    func testCancelledAlarmCannotStartForegroundPlayback() throws {
        let (plugin, delegate, schedule) = try scheduledAlarmFixture()
        let completed = expectation(description: "alarm cancelled before delivery")
        plugin.cancelAlarm(id: schedule.id) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 2)

        XCTAssertTrue(delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule)).isEmpty)
        XCTAssertNil(delegate.audioPlayer)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        withExtendedLifetime(plugin) {}
    }

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

    func testReplacingPlaybackDoesNotOrphanThePreviousPlayer() throws {
        let (plugin, delegate, schedule) = try scheduledAlarmFixture()
        _ = delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule))
        let firstPlayer = try XCTUnwrap(delegate.audioPlayer)
        XCTAssertTrue(firstPlayer.isPlaying)
        let replacement = WarmAlarmScheduleData.from(wire: WarmAlarmScheduleWire(
            id: schedule.id + 1,
            scheduledAtMillis: schedule.scheduledAtMillis,
            notification: WarmAlarmNotificationWire(
                title: "Replacement", body: "Alarm", keepNotificationAfterAlarmEnds: true
            ),
            audio: WarmAlarmAudioWire(
                filePath: schedule.filePath, loop: true, volume: 0, vibrate: false, volumeEnforced: false
            )
        ))
        WarmAlarmStore.shared.save(replacement)
        _ = delegate.handleForegroundDelivery(content: delegate.makeContent(from: replacement))
        let secondPlayer = try XCTUnwrap(delegate.audioPlayer)
        XCTAssertTrue(secondPlayer.isPlaying)
        XCTAssertFalse(firstPlayer.isPlaying)
        let completed = expectation(description: "previous alarm cancelled without stopping replacement")
        plugin.cancelAlarm(id: schedule.id) { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertFalse(firstPlayer.isPlaying)
            XCTAssertTrue(secondPlayer.isPlaying)
            XCTAssertEqual(delegate.currentlyPlayingAlarmId, replacement.id)
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
        let (plugin, delegate, schedule) = try scheduledAlarmFixture()
        _ = delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule))
        let player = try XCTUnwrap(delegate.audioPlayer)
        XCTAssertTrue(player.isPlaying, "The regression fixture must start real looping playback")
        XCTAssertEqual(delegate.currentlyPlayingAlarmId, schedule.id)
        return (plugin, delegate, player, schedule.id)
    }

    private func scheduledAlarmFixture(
        playbackLock: NSRecursiveLock = NSRecursiveLock(),
        onEvent: @escaping (WarmAlarmEventWire) -> Void = { _ in },
        audioPlayerFactory: @escaping (URL) throws -> AVAudioPlayer = { try AVAudioPlayer(contentsOf: $0) }
    ) throws -> (WarmAlarmPlugin, WarmAlarmDelegate, WarmAlarmScheduleData) {
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
            emit: { event, completion in
                onEvent(event)
                completion(true)
            }
        )
        let delegate = WarmAlarmDelegate(
            eventsApi: WarmAlarmEventsApi(binaryMessenger: CancellationTestMessenger()),
            eventQueue: eventQueue,
            playbackLock: playbackLock,
            audioPlayerFactory: audioPlayerFactory
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
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { $0([]) },
            pendingNotificationRemover: { _ in },
            deliveredNotificationRemover: { _ in }
        )
        return (plugin, delegate, schedule)
    }

    private func assertCancellationWaitsForForegroundStartup(cancelAll: Bool) throws {
        let factoryEntered = expectation(description: "foreground validated schedule and entered player factory")
        let releaseFactory = DispatchSemaphore(value: 0)
        let cancellationContended = expectation(description: "cancellation contends for the held playback lock")
        let playbackLock = ContentionReportingLock { cancellationContended.fulfill() }
        let playerLock = NSLock()
        var retainedPlayer: AVAudioPlayer?
        let (plugin, delegate, schedule) = try scheduledAlarmFixture(playbackLock: playbackLock, audioPlayerFactory: { url in
            let player = try AVAudioPlayer(contentsOf: url)
            playerLock.lock()
            retainedPlayer = player
            playerLock.unlock()
            factoryEntered.fulfill()
            XCTAssertEqual(releaseFactory.wait(timeout: .now() + 5), .success)
            return player
        })
        defer { releaseFactory.signal() }
        let foregroundFinished = expectation(description: "foreground startup finishes")
        DispatchQueue.global().async {
            _ = delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule))
            foregroundFinished.fulfill()
        }
        wait(for: [factoryEntered], timeout: 2)
        playerLock.lock()
        let createdPlayer = retainedPlayer
        playerLock.unlock()
        let player = try XCTUnwrap(createdPlayer)
        let cancelledTooSoon = expectation(description: "cancellation must wait for foreground startup")
        cancelledTooSoon.isInverted = true
        let completed = expectation(description: "cancellation completes with playback stopped")
        var didReleaseFactory = false
        let completion: (Result<Void, Error>) -> Void = { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            if !didReleaseFactory { cancelledTooSoon.fulfill() }
            XCTAssertFalse(player.isPlaying)
            XCTAssertNil(delegate.currentlyPlayingAlarmId)
            plugin.isRinging(alarmId: cancelAll ? nil : schedule.id) {
                XCTAssertEqual(try? $0.get(), false)
                completed.fulfill()
            }
        }
        if cancelAll {
            plugin.cancelAllAlarms(completion: completion)
        } else {
            plugin.cancelAlarm(id: schedule.id, completion: completion)
        }
        wait(for: [cancellationContended], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: schedule.id))
        wait(for: [cancelledTooSoon], timeout: 0.05)
        didReleaseFactory = true
        releaseFactory.signal()
        wait(for: [foregroundFinished, completed], timeout: 2)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        withExtendedLifetime(plugin) {}
    }

    private func assertCancellationSuppressesDeliveryBeforeRevalidation(cancelAll: Bool) throws {
        let firstValidationFinished = expectation(description: "foreground pauses before playback revalidation")
        let cancellationContended = expectation(description: "cancellation invalidates the schedule before stop")
        let releaseRevalidation = DispatchSemaphore(value: 0)
        let playbackLock = ContentionReportingLock(
            onAcquisition: { count in
                guard count == 2 else { return }
                firstValidationFinished.fulfill()
                XCTAssertEqual(releaseRevalidation.wait(timeout: .now() + 5), .success)
            },
            onContention: { cancellationContended.fulfill() }
        )
        let (plugin, delegate, schedule) = try scheduledAlarmFixture(
            playbackLock: playbackLock,
            onEvent: { event in
                XCTAssertNotEqual(event.type, .fired, "Invalidated delivery must not emit a fired event")
            },
            audioPlayerFactory: { url in
                XCTFail("Invalidated delivery must not construct a player")
                return try AVAudioPlayer(contentsOf: url)
            }
        )
        defer { releaseRevalidation.signal() }
        let foregroundFinished = expectation(description: "invalidated foreground delivery is suppressed")
        DispatchQueue.global().async {
            XCTAssertTrue(delegate.handleForegroundDelivery(content: delegate.makeContent(from: schedule)).isEmpty)
            foregroundFinished.fulfill()
        }
        wait(for: [firstValidationFinished], timeout: 2)
        let completed = expectation(description: "cancellation completes without playback")
        let completion: (Result<Void, Error>) -> Void = { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertNil(delegate.audioPlayer)
            plugin.isRinging(alarmId: cancelAll ? nil : schedule.id) {
                XCTAssertEqual(try? $0.get(), false)
                completed.fulfill()
            }
        }
        if cancelAll {
            plugin.cancelAllAlarms(completion: completion)
        } else {
            plugin.cancelAlarm(id: schedule.id, completion: completion)
        }
        wait(for: [cancellationContended], timeout: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: schedule.id))
        releaseRevalidation.signal()
        wait(for: [foregroundFinished, completed], timeout: 2)
        withExtendedLifetime(plugin) {}
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

private final class ContentionReportingLock: NSRecursiveLock, @unchecked Sendable {
    private let onAcquisition: (Int) -> Void
    private let onContention: () -> Void
    private var acquisitionCount = 0

    init(onAcquisition: @escaping (Int) -> Void = { _ in }, onContention: @escaping () -> Void) {
        self.onAcquisition = onAcquisition
        self.onContention = onContention
        super.init()
    }

    override func lock() {
        if !super.try() {
            onContention()
            super.lock()
        }
        acquisitionCount += 1
        onAcquisition(acquisitionCount)
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
