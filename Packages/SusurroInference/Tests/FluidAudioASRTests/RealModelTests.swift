import AVFoundation
import Domain
import FluidAudio
import Foundation
import Pipeline
import Testing

@testable import FluidAudioASR

/// Checks against the real Parakeet model. They are off unless `SUSURRO_REAL_MODELS=1`, so CI and the default test run
/// never download a model. The first run downloads about 460 MB into the app's model folder
/// (`~/Library/Application Support/Susurro/Models`); later runs reuse it. They speak with the Spanish system voice
/// Paulina and are skipped when it is not installed:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealModelTests
@Suite(
    "Real Parakeet model",
    .enabled(
        if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
        "Set SUSURRO_REAL_MODELS=1 to check against the real model. The first run downloads about 460 MB."
    ),
    .serialized,
    .timeLimit(.minutes(30))
)
struct RealModelTests {
    private static let sentence =
        "Hola, esto es una prueba de dictado en español. Mañana tengo una reunión a las diez y media con el equipo de ventas. "

    /// FluidAudio's issue 760: the encoder of the default `int8` precision silently corrupts a word that has seconds of
    /// speech after it inside one 15 s window. With the voice Mónica, the default encoder returned "cortazuegos" for
    /// this phrase followed by the tail below; `int8V2` returns it right.
    private static let issue760Phrase = "Por favor, apaga el proceso fondo y revisa la configuración del cortafuegos."
    private static let issue760Tail =
        "Después de la reunión voy a revisar el informe trimestral con el equipo de ventas, y mañana por la tarde enviaré las conclusiones a todos los participantes del proyecto."
    private static let issue760Voice = "Mónica"

    /// The speech after the phrase that the issue needs, and the encoder window the whole clip must fit in, in seconds.
    private static let requiredTrailingSeconds = 6.0
    private static let encoderWindowSeconds = 15.0

    /// How much of a spoken text must come back for a long clip to count as transcribed whole. Speech synthesis and
    /// recognition are both imperfect, so exact equality over minutes of audio would be a flaky test.
    private static let requiredShareOfSentences = 0.75

    /// Skips the test when the voice is missing.
    private static func requireVoice(_ voice: String) throws {
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

    /// Speaks `text` with `voice` into a 16 kHz mono Float32 WAV and reads the samples back.
    private static func speak(_ text: String, voice: String = "Paulina") throws -> [Float] {
        try requireVoice(voice)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "say failed")

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

    /// The words of a text, folded and without punctuation, so "Por favor, apaga" and "por favor apaga" are equal.
    private static func words(_ text: String) -> String {
        fold(text).filter { $0.isLetter || $0 == " " }
    }

    private static func occurrences(of word: String, in text: String) -> Int {
        fold(text).components(separatedBy: word).count - 1
    }

    /// Loads the model. Reports how long that took, and every readiness value published on the way. The first run
    /// includes the download.
    private static func loadedRecognizer() async -> (ParakeetRecognizer, Duration, [RecognizerReadiness]) {
        let recognizer = ParakeetRecognizer()
        var changes = await recognizer.readinessChanges().makeAsyncIterator()
        let started = ContinuousClock.now
        await recognizer.prepare()
        var published: [RecognizerReadiness] = []
        while let readiness = await changes.next() {
            published.append(readiness)
            if readiness == .ready { break }
        }
        return (recognizer, ContinuousClock.now - started, published)
    }

    /// Transcribes `samples` and checks the latency against the limit the coordinator enforces.
    private static func timedTranscript(
        _ samples: [Float],
        by recognizer: ParakeetRecognizer,
        language: String? = nil
    ) async throws -> (text: String, latency: Duration) {
        let started = ContinuousClock.now
        let transcript = try await recognizer.transcribe(
            AudioClip(samples: samples),
            options: RecognitionOptions(language: language)
        )
        let latency = ContinuousClock.now - started
        #expect(latency < DictationLimits.transcriptionTimeout)
        return (transcript.text, latency)
    }

    @Test("a spoken Spanish sentence is transcribed, with the language detected or pinned")
    func spanishSentence() async throws {
        let samples = try Self.speak(Self.sentence)
        let (recognizer, loadTime, published) = await Self.loadedRecognizer()
        print("REAL-MODEL load: \(loadTime), \(published.count) readiness values: \(published)")

        let progress = published.compactMap { readiness -> Double? in
            if case .loading(let progress) = readiness { progress } else { nil }
        }
        #expect(published.last == .ready)
        #expect(progress == progress.sorted())
        #expect(progress.allSatisfy { $0 < 1 })

        for language in [String?.none, "es", "es-CL"] {
            let (text, latency) = try await Self.timedTranscript(samples, by: recognizer, language: language)
            let seconds = Double(samples.count) / 16_000
            print("REAL-MODEL \(seconds) s clip, language \(language ?? "auto"): \"\(text)\" in \(latency)")

            #expect(Self.occurrences(of: "prueba", in: text) == 1)
            #expect(Self.occurrences(of: "dictado", in: text) == 1)
            #expect(Self.occurrences(of: "reunion", in: text) == 1)
        }
    }

    @Test("the weights on disk are the pinned commit, with the re-quantized encoder and not the palettized one")
    func weightsArePinned() async throws {
        _ = await Self.loadedRecognizer()

        let folder = LiveParakeetEngine().modelsDirectory
        let marker = folder.appending(path: ".fluidaudio-revision")
        let stored = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored == LiveParakeetEngine.weightsRevision)
        // A folder that an earlier build filled with the other encoder keeps it; delete the folder to run this check.
        let encoder = LiveParakeetEngine.encoderPrecision.encoderFileName
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: encoder).path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Encoder.mlmodelc").path))
    }

    @Test("a word with seconds of speech after it inside one window comes back right (FluidAudio issue 760)")
    func issue760() async throws {
        let phrase = try Self.speak(Self.issue760Phrase, voice: Self.issue760Voice)
        let clip = try Self.speak(Self.issue760Phrase + " " + Self.issue760Tail, voice: Self.issue760Voice)
        let rate = Double(AudioClip.sampleRate)
        try #require(Double(clip.count - phrase.count) / rate >= Self.requiredTrailingSeconds)
        try #require(Double(clip.count) / rate < Self.encoderWindowSeconds)
        let (recognizer, _, _) = await Self.loadedRecognizer()

        let (text, latency) = try await Self.timedTranscript(clip, by: recognizer)
        print(
            "REAL-MODEL issue 760 case (\(Double(clip.count) / rate) s, \(Double(clip.count - phrase.count) / rate) s after the phrase): \"\(text)\" in \(latency)"
        )

        #expect(Self.words(text).contains(Self.words(Self.issue760Phrase)))
    }

    @Test("silence has no letters, the shortest accepted clip has some, and a clip below it is blank")
    func degenerateClips() async throws {
        let speech = try Self.speak(Self.sentence)
        let (recognizer, _, _) = await Self.loadedRecognizer()
        let minimum = LiveParakeetEngine().minimumSampleCount

        let silence = try await Self.timedTranscript(
            [Float](repeating: 0, count: 2 * AudioClip.sampleRate), by: recognizer)
        let shortest = try await Self.timedTranscript(Array(speech.prefix(minimum)), by: recognizer)
        let below = try await Self.timedTranscript(Array(speech.prefix(minimum - 1)), by: recognizer)
        print("REAL-MODEL silence: \"\(silence.text)\", shortest: \"\(shortest.text)\", below: \"\(below.text)\"")

        #expect(!silence.text.contains { $0.isLetter })
        #expect(shortest.text.contains { $0.isLetter })
        #expect(below.text.allSatisfy { $0.isWhitespace })
    }

    @Test("long clips go to the engine whole", arguments: [10, 20])
    func longClip(repetitions: Int) async throws {
        let samples = try Self.speak(String(repeating: Self.sentence, count: repetitions))
        let (recognizer, _, _) = await Self.loadedRecognizer()

        let (text, latency) = try await Self.timedTranscript(samples, by: recognizer)
        let found = Self.occurrences(of: "dictado", in: text)
        let seconds = Double(samples.count) / 16_000
        print(
            "REAL-MODEL \(seconds) s clip: \(found) of \(repetitions) sentences found, \(text.count) characters, in \(latency)"
        )

        #expect(Double(found) / Double(repetitions) >= Self.requiredShareOfSentences)
    }
}
