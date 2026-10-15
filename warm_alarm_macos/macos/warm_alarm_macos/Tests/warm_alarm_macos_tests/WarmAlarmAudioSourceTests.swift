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

    func testForegroundCustomFileDoesNotRequestDuplicateNotificationSound() throws {
        let file = try makeAudioFile()
        let (delegate, content) = foregroundAudioFixture(filePath: file.path)

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert])
        XCTAssertEqual(delegate.currentlyPlayingAlarmId, 7_070_002)
    }

    func testForegroundCustomAssetDoesNotRequestDuplicateNotificationSound() {
        let (delegate, content) = foregroundAudioFixture(assetPath: "assets/custom-alarm.caf")

        XCTAssertEqual(delegate.handleForegroundDelivery(content: content), [.alert])
    }

    private func foregroundAudioFixture(
        filePath: String? = nil,
        assetPath: String? = nil
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
            eventQueue: queue
        )
        WarmAlarmStore.shared.save(schedule)
        addTeardownBlock {
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
