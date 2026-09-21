import XCTest

@testable import warm_alarm_macos

final class WarmAlarmAudioSourceTests: XCTestCase {
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
