import AVFoundation
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmAudioSourceTests: XCTestCase {
    func testForegroundDefaultAudioRequestsNotificationSound() {
        let (delegate, content) = foregroundAudioFixture()
        let options = delegate.handleForegroundDelivery(content: content)

        XCTAssertEqual(options, [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertNotNil(content.sound)
    }

    func testForegroundEmptyAudioSourcesRequestNotificationSound() {
        let (delegate, content) = foregroundAudioFixture(filePath: "", assetPath: "")

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
    }

    func testForegroundCancelledAlarmDoesNotRequestNotificationSound() throws {
        let (delegate, content) = foregroundAudioFixture()
        let schedule = try XCTUnwrap(WarmAlarmStore.shared.load(id: 7_070_002))
        defer { WarmAlarmStore.shared.save(schedule) }
        WarmAlarmStore.shared.remove(id: 7_070_002)

        XCTAssertTrue(delegate.handleForegroundDelivery(content: content).isEmpty)
    }

    func testForegroundCustomFileDoesNotRequestDuplicateNotificationSound() throws {
        let file = try makeAudioFile()
        let (delegate, content) = foregroundAudioFixture(filePath: file.path)

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert])
        XCTAssertEqual(delegate.currentlyPlayingAlarmId, 7_070_002)
    }

    func testForegroundReplacementRejectsPreviousNotificationContent() {
        let (delegate, previousContent) = foregroundAudioFixture()
        let (_, currentContent) = foregroundAudioFixture()

        XCTAssertTrue(delegate.handleForegroundDelivery(content: previousContent).isEmpty)
        XCTAssertEqual(delegate.handleForegroundDelivery(content: currentContent), [.alert, .sound])
    }

    func testUnrelatedNotificationWithUnknownAlarmIdRetainsPresentation() throws {
        let (delegate, originalContent) = foregroundAudioFixture()
        let content = try XCTUnwrap(originalContent.mutableCopy() as? UNMutableNotificationContent)
        content.categoryIdentifier = "HOST_NOTIFICATION"
        content.userInfo = ["alarmId": "-7070002"]

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
    }

    func testLegacyForegroundNotificationRemainsValidUntilScheduleReplacement() throws {
        let (delegate, currentContent) = foregroundAudioFixture()
        let schedule = try XCTUnwrap(WarmAlarmStore.shared.load(id: 7_070_002))
        let encoded = try JSONEncoder().encode(schedule)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyJSON.removeValue(forKey: "occurrenceSeriesToken")
        let legacy = try JSONDecoder().decode(
            WarmAlarmScheduleData.self, from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        WarmAlarmStore.shared.save(legacy)
        let legacyContent = delegate.makeContent(from: legacy)

        XCTAssertEqual(delegate.handleForegroundDelivery(content: legacyContent), [.alert, .sound])
        WarmAlarmStore.shared.save(schedule)
        XCTAssertTrue(delegate.handleForegroundDelivery(content: legacyContent).isEmpty)
        XCTAssertEqual(delegate.handleForegroundDelivery(content: currentContent), [.alert, .sound])
    }

    func testScheduleCopiesPreserveForegroundNotificationGeneration() throws {
        let (delegate, content) = foregroundAudioFixture()
        let schedule = try XCTUnwrap(WarmAlarmStore.shared.load(id: 7_070_002))
        WarmAlarmStore.shared.save(
            schedule.withActiveSnooze(untilMillis: 1_900_000_060_000).withRecurrenceTime(hour: 8, minute: 30)
        )

        XCTAssertEqual(
            delegate.handleForegroundDelivery(content: content, deliveredAtMillis: 1_900_000_060_000), [.alert, .sound]
        )
    }

    func testUnrelatedNotificationWithMatchingAlarmIdDoesNotStartPlayer() throws {
        let file = try makeAudioFile()
        let (delegate, originalContent) = foregroundAudioFixture(filePath: file.path)
        let content = try XCTUnwrap(originalContent.mutableCopy() as? UNMutableNotificationContent)
        content.categoryIdentifier = "HOST_NOTIFICATION"

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testForegroundMissingAssetFallsBackToNotificationSound() throws {
        let (delegate, content) = foregroundAudioFixture(assetPath: "assets/missing-alarm.caf")
        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testForegroundMissingFileFallsBackToNotificationSound() throws {
        let (delegate, content) = foregroundAudioFixture(filePath: "/missing/\(UUID().uuidString).caf")
        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testForegroundCorruptFileFallsBackToNotificationSound() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        try Data("not audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let (delegate, content) = foregroundAudioFixture(filePath: file.path)
        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testForegroundRejectedPlaybackFallsBackToNotificationSound() throws {
        let file = try makeAudioFile()
        let (delegate, content) = foregroundAudioFixture(filePath: file.path, playAudio: { _ in false })
        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert, .sound])
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testRegistrationPreservesHostCategoriesAndDistinctCustomTitles() throws {
        let (delegate, _) = foregroundAudioFixture()
        func content(stop: String, snooze: String) -> UNNotificationContent {
            let wire = WarmAlarmScheduleWire(
                id: 7_070_002, scheduledAtMillis: 1_900_000_000_000,
                notification: WarmAlarmNotificationWire(
                    title: "Labels", body: "Alarm", stopActionTitle: stop, snoozeActionTitle: snooze,
                    keepNotificationAfterAlarmEnds: true
                ),
                audio: WarmAlarmAudioWire(loop: false, vibrate: false, volumeEnforced: false)
            )
            return delegate.makeContent(from: WarmAlarmScheduleData.from(wire: wire))
        }
        let first = content(stop: "Dismiss A", snooze: "Later A")
        let second = content(stop: "Dismiss B", snooze: "Later B")
        XCTAssertNotEqual(first.categoryIdentifier, second.categoryIdentifier)
        let proxy = WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: delegate, forwardingDelegate: nil)
        XCTAssertTrue(proxy.target(for: first) === delegate)
        XCTAssertTrue(proxy.target(for: second) === delegate)
        let unrelated = UNMutableNotificationContent()
        unrelated.categoryIdentifier = "WARM_ALARM:HOST_MESSAGES"
        XCTAssertNil(proxy.target(for: unrelated))
        let host = UNNotificationCategory(identifier: "HOST_MESSAGES", actions: [], intentIdentifiers: [], options: [])
        var registered: Set<UNNotificationCategory> = [host]
        let done = expectation(description: "categories registered")
        WarmAlarmDelegate.registerCategories(
            for: [first, second], read: { $0(registered) }, write: { registered = $0 }
        ) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(registered.contains(host))
        let firstCategory = try XCTUnwrap(registered.first { $0.identifier == first.categoryIdentifier })
        let secondCategory = try XCTUnwrap(registered.first { $0.identifier == second.categoryIdentifier })
        XCTAssertEqual(firstCategory.actions.map(\.title), ["Dismiss A", "Later A"])
        XCTAssertEqual(secondCategory.actions.map(\.title), ["Dismiss B", "Later B"])
        XCTAssertEqual(firstCategory.actions.map(\.identifier), ["STOP", "SNOOZE"])
    }

    private func foregroundAudioFixture(
        filePath: String? = nil,
        assetPath: String? = nil,
        playAudio: @escaping (AVAudioPlayer) -> Bool = { $0.play() }
    ) -> (WarmAlarmDelegate, UNNotificationContent) {
        let wire = WarmAlarmScheduleWire(
            id: 7_070_002,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Foreground audio", body: "Alarm", keepNotificationAfterAlarmEnds: true
            ),
            audio: WarmAlarmAudioWire(
                filePath: filePath, assetPath: assetPath, loop: false, vibrate: false, volumeEnforced: false
            )
        )
        let schedule = WarmAlarmScheduleData.from(wire: wire)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = WarmAlarmEventQueue(
            store: WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(
                fileURL: directory.appendingPathComponent("events.json")
            )),
            emit: { _, completion in completion(true) }
        )
        let delegate = WarmAlarmDelegate(
            eventsApi: WarmAlarmEventsApi(binaryMessenger: ForegroundAudioTestMessenger()),
            eventQueue: queue,
            playAudio: playAudio
        )
        WarmAlarmStore.shared.save(schedule)
        addTeardownBlock {
            WarmAlarmStore.shared.save(schedule)
            delegate.handleStop(alarmId: wire.id)
            WarmAlarmStore.shared.remove(id: wire.id)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return (delegate, delegate.makeContent(from: schedule))
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 8_000)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testAssetURLFindsAudioInsideAppFramework() throws {
        let bundle = try makeBundle()
        let asset = "assets/audio/alarm_ring.wav"
        let expected = try XCTUnwrap(bundle.privateFrameworksURL)
            .appendingPathComponent("App.framework/Resources/flutter_assets/\(asset)")
        try writeAsset(to: expected)

        XCTAssertEqual(WarmAlarmAudioSource.assetURL(for: asset, in: bundle)?.path, expected.path)
    }

    func testAssetURLRetainsMainBundleFallback() throws {
        let bundle = try makeBundle()
        let asset = "assets/audio/alarm_ring.wav"
        let expected = try XCTUnwrap(bundle.resourceURL)
            .appendingPathComponent("flutter_assets/\(asset)")
        try writeAsset(to: expected)

        XCTAssertEqual(WarmAlarmAudioSource.assetURL(for: asset, in: bundle)?.path, expected.path)
    }

    func testAssetURLReturnsNilForMissingAudio() throws {
        let bundle = try makeBundle()
        XCTAssertNil(WarmAlarmAudioSource.assetURL(for: "assets/missing.wav", in: bundle))
    }

    private func makeBundle() throws -> Bundle {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Example.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.warm-alarm.\(UUID().uuidString)", "CFBundlePackageType": "APPL"],
            format: .xml,
            options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(Bundle(url: app))
    }

    private func writeAsset(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("asset fixture".utf8).write(to: url)
    }

    func testFadeRampPrefersExplicitSteps() throws {
        let steps = [FadeStep(timeMillis: 0, volume: 0.2), FadeStep(timeMillis: 500, volume: 0.6)]
        let resolved = try XCTUnwrap(
            WarmAlarmFadeRamp.resolve(fadeSteps: steps, fadeInDurationMillis: 3_000, volume: 1.0)
        )

        XCTAssertEqual(resolved.map(\.timeMillis), [0, 500])
        XCTAssertEqual(resolved.map(\.volume), [0.2, 0.6])
    }

    func testFadeRampIsNilWithoutPositiveDuration() {
        XCTAssertNil(WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: nil, volume: 0.5))
        XCTAssertNil(WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: 0, volume: 0.5))
        XCTAssertNil(WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: -100, volume: 0.5))
    }

    func testFadeRampUsesTenStepsForLongDurations() throws {
        let resolved = try XCTUnwrap(
            WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: 3_000, volume: 0.8)
        )

        XCTAssertEqual(resolved.map(\.timeMillis), stride(from: 0, through: 3_000, by: 300).map { Int64($0) })
        XCTAssertEqual(resolved.first?.volume, 0.0)
        XCTAssertEqual(resolved[5].volume, 0.4, accuracy: 1e-9)
        XCTAssertEqual(resolved.last?.volume, 0.8)
    }

    func testFadeRampUsesOneStepPerHundredMillisForShortDurations() throws {
        let resolved = try XCTUnwrap(
            WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: 250, volume: nil)
        )

        XCTAssertEqual(resolved.map(\.timeMillis), [0, 125, 250])
        XCTAssertEqual(resolved.map(\.volume), [0.0, 0.5, 1.0])
    }

    func testFadeRampUsesOneStepBelowHundredMillis() throws {
        let resolved = try XCTUnwrap(
            WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: 50, volume: 1.5)
        )

        XCTAssertEqual(resolved.map(\.timeMillis), [0, 50])
        XCTAssertEqual(resolved.map(\.volume), [0.0, 1.0])
    }

    func testVolumeEnforcerStartsAfterTheDerivedRampEnds() {
        let ramp = WarmAlarmFadeRamp.resolve(fadeSteps: nil, fadeInDurationMillis: 3_000, volume: 0.8)

        XCTAssertEqual(WarmAlarmFadeRamp.volumeEnforcerStartMillis(for: ramp), 3_000)
    }

    func testVolumeEnforcerStartsAfterExplicitFadeStepsEnd() {
        let steps = [FadeStep(timeMillis: 0, volume: 0.2), FadeStep(timeMillis: 1_500, volume: 0.6)]

        XCTAssertEqual(WarmAlarmFadeRamp.volumeEnforcerStartMillis(for: steps), 1_500)
    }

    func testVolumeEnforcerStartsImmediatelyWithoutAFade() {
        XCTAssertEqual(WarmAlarmFadeRamp.volumeEnforcerStartMillis(for: nil), 0)
        XCTAssertEqual(WarmAlarmFadeRamp.volumeEnforcerStartMillis(for: []), 0)
        XCTAssertEqual(WarmAlarmFadeRamp.volumeEnforcerStartMillis(for: [FadeStep(timeMillis: 0, volume: 0.5)]), 0)
    }

    func testSelectReturnsNoneWithoutSources() {
        XCTAssertEqual(WarmAlarmAudioSource.select(filePath: nil, assetPath: nil), .none)
    }

    func testSelectReturnsFileForFileOnly() {
        XCTAssertEqual(WarmAlarmAudioSource.select(filePath: "/voice.m4a", assetPath: nil), .file("/voice.m4a"))
    }

    func testSelectReturnsAssetForAssetOnly() {
        XCTAssertEqual(WarmAlarmAudioSource.select(filePath: nil, assetPath: "assets/tone.mp3"), .asset("assets/tone.mp3"))
    }

    func testSelectPrefersFileWhenBothSourcesArePresent() {
        XCTAssertEqual(
            WarmAlarmAudioSource.select(filePath: "/voice.m4a", assetPath: "assets/tone.mp3"),
            .file("/voice.m4a")
        )
    }

    func testSelectFallsBackToAssetForAnEmptyFilePath() {
        XCTAssertEqual(
            WarmAlarmAudioSource.select(filePath: "", assetPath: "assets/tone.mp3"),
            .asset("assets/tone.mp3")
        )
    }

    func testSelectReturnsNoneForAnEmptyAssetPath() {
        XCTAssertEqual(WarmAlarmAudioSource.select(filePath: nil, assetPath: ""), .none)
    }

    func testSelectRetainsAWhitespaceFilePath() {
        XCTAssertEqual(
            WarmAlarmAudioSource.select(filePath: " ", assetPath: "assets/tone.mp3"),
            .file(" ")
        )
    }
}

private final class ForegroundAudioTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
