import AVFoundation
import Domain
import Foundation
import Testing

@testable import AudioIO

@Suite("CAF clip loader", .timeLimit(.minutes(1)))
struct CAFClipLoaderTests {
    /// Writes a CAF of 16-bit samples at `sampleRate` and returns its folder and file.
    private static func writeCAF(samples: [Float], sampleRate: Double = 16_000, channels: AVAudioChannelCount = 1) throws
        -> (folder: URL, file: URL)
    {
        let folder = FileManager.default.temporaryDirectory.appending(path: "susurro-caf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "clip.caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        // The file is closed, and finished, when `output` goes away at the end of this function.
        let output = try AVAudioFile(forWriting: file, settings: settings)
        guard !samples.isEmpty else { return (folder, file) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let frames = AVAudioFrameCount(samples.count / Int(channels))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = samples[frame * Int(channels) + channel] }
        }
        try output.write(from: buffer)
        return (folder, file)
    }

    @Test("a 16 kHz mono recording reads back as the samples it was written with")
    func readsBackSamples() async throws {
        let samples: [Float] = (0..<1_600).map { Float(sin(Double($0) / 20)) * 0.5 }
        let (folder, file) = try Self.writeCAF(samples: samples)
        defer { try? FileManager.default.removeItem(at: folder) }

        let clip = try await CAFClipLoader().clip(at: file)

        #expect(clip.samples.count == samples.count)
        // 16-bit storage rounds each sample to a step of about 3e-5.
        for (read, written) in zip(clip.samples, samples) { #expect(abs(read - written) < 0.001) }
    }

    @Test("a recording that is not 16 kHz mono is refused, since the recognizer cannot take it as it is")
    func refusesOtherFormats() async throws {
        let (folder, file) = try Self.writeCAF(samples: Array(repeating: 0.1, count: 4_800), sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: CAFClipLoader.LoadError.unsupportedFormat) { try await CAFClipLoader().clip(at: file) }
    }

    @Test("a file that is not there is an error")
    func missingFile() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "susurro-missing-\(UUID().uuidString).caf")

        await #expect(throws: (any Error).self) { try await CAFClipLoader().clip(at: missing) }
    }

    @Test("an empty recording is an error")
    func emptyFile() async throws {
        let (folder, file) = try Self.writeCAF(samples: [])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: CAFClipLoader.LoadError.empty) { try await CAFClipLoader().clip(at: file) }
    }
}
