import AVFoundation
import Foundation
import Testing

/// The switch of every check in this target. They run the real speech models, the real recording files, and the real
/// Whisper install, so they are off unless `SUSURRO_REAL_MODELS=1`, and CI compiles them and skips them:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroFeatures --filter RealModelPipelineTests
extension Trait where Self == ConditionTrait {
    static var realModels: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
            "Set SUSURRO_REAL_MODELS=1 to run against the real models. The first run downloads about 600 MB.")
    }
}

/// Spanish speech for the checks that need a voice: the system's `say`, written to a 16 kHz mono Float32 WAV and read
/// back as samples, the format the recognizers take.
enum SpokenClip {
    static let sampleRate = 16_000

    /// Skips the test when the voice is not installed.
    static func requireVoice(_ voice: String) throws {
        let voices = Process()
        voices.executableURL = URL(filePath: "/usr/bin/say")
        voices.arguments = ["-v", "?"]
        let output = Pipe()
        voices.standardOutput = output
        try voices.run()
        let listing = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        voices.waitUntilExit()
        if !listing.split(separator: "\n").contains(where: { $0.hasPrefix(voice) }) {
            try Test.cancel("The Spanish voice \(voice) is not installed.")
        }
    }

    /// `text` spoken by `voice`, without the silence around it.
    static func speak(_ text: String, voice: String = "Paulina") throws -> [Float] {
        try requireVoice(voice)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@\(sampleRate)", text]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "say failed")

        let file = try AVAudioFile(forReading: url)
        try #require(Int(file.processingFormat.sampleRate) == sampleRate && file.processingFormat.channelCount == 1)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(sampleRate)))
    }

    static func seconds(_ samples: [Float]) -> Double {
        Double(samples.count) / Double(sampleRate)
    }

    /// The words of a text, folded and without punctuation, so "Por favor, apaga" and "por favor apaga" are equal.
    static func words(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .filter { $0.isLetter || $0 == " " }
    }
}

extension Duration {
    /// Milliseconds, for the numbers the checks print.
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
