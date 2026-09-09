import AVFAudio
import Foundation
import Synchronization

enum WarmAlarmSoundFiles {
    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    static func ownedURL(named name: String?, directory: URL = directory) -> URL? {
        guard let name, name.hasPrefix("warm-alarm-"), name.hasSuffix(".caf"),
              !name.contains("/"), !name.contains("\\") else { return nil }
        return directory.appendingPathComponent(name)
    }

    static func remove(named name: String?, directory: URL = directory) {
        guard let url = ownedURL(named: name, directory: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @available(iOS 26.0, macOS 15.0, *)
    static func prepare(primary: URL, background: URL?, directory: URL = directory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("warm-alarm-\(UUID().uuidString).caf")
        do {
            try WarmAlarmSoundRenderer.render(primary: primary, background: background, to: output)
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: output.path
            )
            #endif
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}

@available(iOS 26.0, macOS 15.0, *)
enum WarmAlarmSoundRenderer {
    private final class ConverterInput: Sendable {
        private struct State {
            let buffer: AVAudioPCMBuffer
            var position: AVAudioFrameCount = 0
        }

        private let state: Mutex<State>

        init(_ buffer: sending AVAudioPCMBuffer) {
            state = Mutex(State(buffer: buffer))
        }

        func next(_ count: AVAudioPacketCount, status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            state.withLock { state in
                let remaining = state.buffer.frameLength - state.position
                guard remaining > 0,
                      let chunk = AVAudioPCMBuffer(pcmFormat: state.buffer.format, frameCapacity: min(count, remaining))
                else {
                    status.pointee = .endOfStream
                    return nil
                }
                chunk.frameLength = chunk.frameCapacity
                for channel in 0..<Int(chunk.format.channelCount) {
                    chunk.floatChannelData![channel].update(
                        from: state.buffer.floatChannelData![channel].advanced(by: Int(state.position)),
                        count: Int(chunk.frameLength)
                    )
                }
                state.position += chunk.frameLength
                status.pointee = .haveData
                return chunk
            }
        }
    }

    static func render(primary: URL, background: URL?, to output: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let voice = try decode(primary, format: format)
        let tone = try background.map { try decode($0, format: format) }
        if let tone {
            let voiceFrames = Int(voice.frameLength)
            let toneFrames = Int(tone.frameLength)
            for channel in 0..<Int(format.channelCount) {
                let destination = voice.floatChannelData![channel]
                let source = tone.floatChannelData![channel]
                for frame in 0..<voiceFrames {
                    destination[frame] = 0.5 * destination[frame] + 0.5 * source[frame % toneFrames]
                }
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: output, settings: settings)
        defer { file.close() }
        try file.write(from: voice)
    }

    private static func decode(_ url: URL, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0,
              file.length <= Int64(UInt32.max),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else {
            throw NSError(domain: "WarmAlarmSoundRenderer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The alarm sound has no readable audio frames."
            ])
        }
        let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096)!
        while input.frameLength < input.frameCapacity {
            try file.read(into: chunk, frameCount: min(chunk.frameCapacity, input.frameCapacity - input.frameLength))
            guard chunk.frameLength > 0 else { break }
            for channel in 0..<Int(input.format.channelCount) {
                input.floatChannelData![channel].advanced(by: Int(input.frameLength)).update(
                    from: chunk.floatChannelData![channel],
                    count: Int(chunk.frameLength)
                )
            }
            input.frameLength += chunk.frameLength
        }
        let frames = ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)
        let capacity = frames + 1_024
        guard capacity <= Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)),
              let converter = AVAudioConverter(from: input.format, to: format)
        else {
            throw NSError(domain: "WarmAlarmSoundRenderer", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The alarm sound cannot be converted to PCM audio."
            ])
        }
        converter.primeMethod = .none
        let provider = ConverterInput(input)
        var conversionError: NSError?
        let result = converter.convert(to: output, error: &conversionError) { count, status in
            provider.next(count, status: status)
        }
        guard result != .error, output.frameLength > 0 else {
            throw conversionError ?? NSError(domain: "WarmAlarmSoundRenderer", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The alarm sound conversion produced no audio."
            ])
        }
        output.frameLength = min(output.frameLength, AVAudioFrameCount(frames))
        return output
    }
}
