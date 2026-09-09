import AVFAudio
import XCTest

@testable import warm_alarm_ios

@available(iOS 26.0, macOS 15.0, *)
final class WarmAlarmSoundRendererTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testRenderPreservesTwoMinuteRecordingThroughItsLastSamples() throws {
        var samples = [Float](repeating: 0.2, count: 8_000 * 120)
        samples.replaceSubrange((samples.count - 8_000)..., with: repeatElement(Float(0.7), count: 8_000))
        let voice = try fixture("voice.caf", samples: samples, sampleRate: 8_000)
        let output = directory.appendingPathComponent("alarm.caf")

        try WarmAlarmSoundRenderer.render(primary: voice, background: nil, to: output)

        let decoded = try read(output)
        XCTAssertEqual(decoded.format.sampleRate, 44_100)
        XCTAssertEqual(decoded.format.channelCount, 2)
        XCTAssertEqual(Double(decoded.frameLength) / decoded.format.sampleRate, 120, accuracy: 0.001)
        let lastSecond = Int(decoded.frameLength) - 44_100
        XCTAssertEqual(decoded.floatChannelData![0][lastSecond + 22_050], 0.7, accuracy: 0.001)
        XCTAssertEqual(decoded.floatChannelData![1][lastSecond + 22_050], 0.7, accuracy: 0.001)
    }

    func testRenderMixesBothSourcesAndRepeatsShortBackgroundForWholeVoice() throws {
        let voice = try fixture("voice.caf", samples: [Float](repeating: 0.4, count: 44_100 * 4))
        let tone = try fixture("tone.caf", samples: [Float](repeating: 0.2, count: 44_100))
        let output = directory.appendingPathComponent("mixed.caf")

        try WarmAlarmSoundRenderer.render(primary: voice, background: tone, to: output)

        let decoded = try read(output)
        XCTAssertEqual(decoded.frameLength, 44_100 * 4)
        for second in 0..<4 {
            XCTAssertEqual(decoded.floatChannelData![0][second * 44_100 + 1_000], 0.3, accuracy: 0.001)
            XCTAssertEqual(decoded.floatChannelData![1][second * 44_100 + 1_000], 0.3, accuracy: 0.001)
        }
    }

    func testRenderRejectsMissingRequestedVoiceWithoutProducingDefaultSound() throws {
        let output = directory.appendingPathComponent("missing.caf")

        XCTAssertThrowsError(try WarmAlarmSoundRenderer.render(
            primary: directory.appendingPathComponent("does-not-exist.m4a"),
            background: nil,
            to: output
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testSoundFilesRemoveOnlyOwnedFilesAndPreserveRecording() throws {
        let recording = try fixture("voice.caf", samples: [Float](repeating: 0.2, count: 8_000))
        let output = try WarmAlarmSoundFiles.prepare(primary: recording, background: nil, directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        WarmAlarmSoundFiles.remove(named: recording.lastPathComponent, directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
        WarmAlarmSoundFiles.remove(named: "../" + output.lastPathComponent, directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        WarmAlarmSoundFiles.remove(named: output.lastPathComponent, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }

    #if os(iOS)
    func testAlarmKitAlertDoesNotStartASecondNativePlayer() throws {
        let voice = try fixture("voice.caf", samples: [Float](repeating: 0.2, count: 44_100))
        let schedule = WarmAlarmScheduleData.from(wire: WarmAlarmScheduleWire(
            id: 918_311,
            scheduledAtMillis: 1,
            notification: WarmAlarmNotificationWire(title: "Alarm", body: "", keepNotificationAfterAlarmEnds: false),
            audio: WarmAlarmAudioWire(filePath: voice.path, loop: true, vibrate: false, volumeEnforced: false)
        )).withAlarmKitManaged(true)
        let fired = expectation(description: "AlarmKit fired event")
        let events = SoundTestEvents { fired.fulfill() }
        let delegate = WarmAlarmDelegate(
            eventsApi: events,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "sound-test")
        )
        defer {
            delegate.stopIfPlaying(alarmId: schedule.id)
            WarmAlarmStore.shared.remove(id: schedule.id)
        }

        delegate.handleAlarmKitAlert(schedule: schedule)

        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        wait(for: [fired], timeout: 5)
        XCTAssertEqual(events.events.count, 1)
    }
    #endif

    func testRenderDecodesAACRecordingThroughItsLastSecond() throws {
        let input = directory.appendingPathComponent("recording.aac")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100 * 120)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(buffer.frameLength) {
                let amplitude = frame >= 44_100 * 119 ? 0.7 : 0.2
                buffer.floatChannelData![channel][frame] = Float(amplitude * sin(Double(frame) * 440 * 2 * .pi / 44_100))
            }
        }
        let file = try AVAudioFile(forWriting: input, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        try file.write(from: buffer)
        file.close()
        let recorded = try read(input)
        let output = directory.appendingPathComponent("decoded.caf")

        try WarmAlarmSoundRenderer.render(primary: input, background: nil, to: output)

        let decoded = try read(output)
        XCTAssertGreaterThanOrEqual(recorded.frameLength, 44_100 * 120)
        XCTAssertEqual(decoded.frameLength, recorded.frameLength)
        for channel in 0..<2 {
            let start = 44_100 * 119 + 11_025
            let energy = (start..<(start + 22_050)).reduce(0.0) { sum, frame in
                let sample = Double(decoded.floatChannelData![channel][frame])
                return sum + sample * sample
            }
            XCTAssertEqual(sqrt(energy / 22_050), 0.7 / sqrt(2), accuracy: 0.02)
        }
    }

    private func fixture(_ name: String, samples: [Float], sampleRate: Double = 44_100) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        defer { file.close() }
        try file.write(from: buffer)
        return url
    }

    private func read(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096)!
        while buffer.frameLength < buffer.frameCapacity {
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, buffer.frameCapacity - buffer.frameLength))
            guard chunk.frameLength > 0 else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                buffer.floatChannelData![channel].advanced(by: Int(buffer.frameLength)).update(
                    from: chunk.floatChannelData![channel],
                    count: Int(chunk.frameLength)
                )
            }
            buffer.frameLength += chunk.frameLength
        }
        return buffer
    }
}

#if os(iOS)
private final class SoundTestEvents: WarmAlarmEventsApiProtocol {
    var events: [WarmAlarmEventWire] = []
    let onEvent: () -> Void
    init(onEvent: @escaping () -> Void) { self.onEvent = onEvent }
    func emitEvent(event: WarmAlarmEventWire, completion: @escaping (Result<Void, PigeonError>) -> Void) {
        events.append(event)
        onEvent()
        completion(.success(()))
    }
}
#endif
