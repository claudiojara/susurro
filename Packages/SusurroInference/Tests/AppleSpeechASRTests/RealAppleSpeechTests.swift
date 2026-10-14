import AVFoundation
import Domain
import Foundation
import Testing

@testable import AppleSpeechASR

/// Checks against the real on-device speech framework. They are off unless `SUSURRO_REAL_MODELS=1`, so CI and the default
/// test run never install a language. The first run installs the Spanish assets (the system downloads them). The speech
/// comes from the Spanish system voice Paulina, and the test is skipped when it is not installed:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealAppleSpeechTests
@Suite(
    "Real Apple speech",
    .enabled(
        if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
        "Set SUSURRO_REAL_MODELS=1 to check against the real speech framework."
    ),
    .serialized,
    .timeLimit(.minutes(10))
)
struct RealAppleSpeechTests {
    private static let sentence =
        "Hola, esto es una prueba de dictado en español. Mañana tengo una reunión con el equipo."

    /// Speaks `text` with Paulina into a 16 kHz mono Float32 WAV and reads the samples back.
    private static func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", "Paulina", "-o", url.path, "--data-format=LEF32@16000", text]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "say failed (is the voice Paulina installed?)")
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    @Test("the framework installs Spanish and transcribes a spoken sentence in Spanish")
    func transcribesSpanish() async throws {
        let samples = try Self.speak(Self.sentence)
        let recognizer = AppleSpeechRecognizer()
        await recognizer.prepare()
        var readiness = await recognizer.readiness()
        let started = ContinuousClock.now
        while case .loading = readiness, ContinuousClock.now - started < .seconds(300) {
            try await Task.sleep(for: .milliseconds(200))
            readiness = await recognizer.readiness()
        }
        print("REAL-APPLE readiness after install: \(readiness) in \(ContinuousClock.now - started)")
        try #require(readiness == .ready)

        let began = ContinuousClock.now
        let transcript = try await recognizer.transcribe(
            AudioClip(samples: samples), options: RecognitionOptions(language: "es"))
        print("REAL-APPLE: \"\(transcript.text)\" in \(ContinuousClock.now - began)")

        let folded = transcript.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        #expect(folded.contains("prueba"))
        #expect(folded.contains("dictado"))
    }
}
