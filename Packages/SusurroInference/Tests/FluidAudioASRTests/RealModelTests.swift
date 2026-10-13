import AVFoundation
import Domain
import Foundation
import Testing

@testable import FluidAudioASR

/// Checks against the real Parakeet model. They are off unless `SUSURRO_REAL_MODELS=1`, so CI and the default test run
/// never download a model. The first run downloads about 460 MB into FluidAudio's cache; later runs reuse it. They need
/// the Spanish system voice Paulina:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealModelTests
@Suite(
    "Real Parakeet model",
    .enabled(if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1"),
    .serialized,
    .timeLimit(.minutes(30))
)
struct RealModelTests {
    private static let sentence =
        "Hola, esto es una prueba de dictado en español. Mañana tengo una reunión a las diez y media con el equipo de ventas. "

    /// Speaks `text` with the voice Paulina into a 16 kHz mono Float32 WAV and reads the samples back.
    private static func speak(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", "Paulina", "-o", url.path, "--data-format=LEF32@16000", text]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "say failed; is the voice Paulina installed?")

        let file = try AVAudioFile(forReading: url)
        try #require(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }

    private static func occurrences(of word: String, in text: String) -> Int {
        fold(text).components(separatedBy: word).count - 1
    }

    /// Loads the model and reports how long that took. The first run includes the download.
    private static func loadedRecognizer() async -> (ParakeetRecognizer, Duration) {
        let recognizer = ParakeetRecognizer()
        let started = ContinuousClock.now
        await recognizer.prepare()
        await recognizer.waitUntilReady()
        return (recognizer, ContinuousClock.now - started)
    }

    @Test("a spoken Spanish sentence is transcribed, with the language detected or pinned")
    func spanishSentence() async throws {
        let samples = try Self.speak(Self.sentence)
        let (recognizer, loadTime) = await Self.loadedRecognizer()
        print("REAL-MODEL load: \(loadTime)")

        for language in [String?.none, "es"] {
            let started = ContinuousClock.now
            let transcript = try await recognizer.transcribe(
                AudioClip(samples: samples),
                options: RecognitionOptions(language: language)
            )
            let latency = ContinuousClock.now - started
            let seconds = Double(samples.count) / 16_000
            print("REAL-MODEL \(seconds) s clip, language \(language ?? "auto"): \"\(transcript.text)\" in \(latency)")

            #expect(Self.occurrences(of: "prueba", in: transcript.text) == 1)
            #expect(Self.occurrences(of: "dictado", in: transcript.text) == 1)
            #expect(Self.occurrences(of: "reunion", in: transcript.text) == 1)
        }
    }

    @Test("long clips go to the engine whole", arguments: [10, 20])
    func longClip(repetitions: Int) async throws {
        let samples = try Self.speak(String(repeating: Self.sentence, count: repetitions))
        let (recognizer, _) = await Self.loadedRecognizer()

        let started = ContinuousClock.now
        let transcript = try await recognizer.transcribe(AudioClip(samples: samples), options: RecognitionOptions())
        let latency = ContinuousClock.now - started
        let seconds = Double(samples.count) / 16_000
        let found = Self.occurrences(of: "dictado", in: transcript.text)
        print(
            "REAL-MODEL \(seconds) s clip: \(found) of \(repetitions) sentences found, \(transcript.text.count) characters, in \(latency)"
        )

        #expect(found >= repetitions * 3 / 4)
    }
}
