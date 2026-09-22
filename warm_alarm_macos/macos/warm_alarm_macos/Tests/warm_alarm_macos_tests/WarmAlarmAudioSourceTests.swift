import XCTest

@testable import warm_alarm_macos

final class WarmAlarmAudioSourceTests: XCTestCase {
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
