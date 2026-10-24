import XCTest

@testable import warm_alarm_ios

final class WarmAlarmAudioSourceTests: XCTestCase {
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
