import AVFoundation
import Domain
import FluidAudio
import Foundation
import Pipeline
import Testing

@testable import FluidAudioASR

/// Checks against the real Parakeet model. They are off unless `SUSURRO_REAL_MODELS=1`, so CI and the default test run
/// never download a model. The first run downloads about 600 MB into the app's model folder
/// (`~/Library/Application Support/Susurro/Models`); later runs reuse it. They speak with the Spanish system voices
/// Paulina and, for one check, Mónica, and each test is skipped when its voice is not installed:
///
///     SUSURRO_REAL_MODELS=1 swift test --package-path Packages/SusurroInference --filter RealModelTests
@Suite(
    "Real Parakeet model",
    .enabled(
        if: ProcessInfo.processInfo.environment["SUSURRO_REAL_MODELS"] == "1",
        "Set SUSURRO_REAL_MODELS=1 to check against the real model. The first run downloads about 600 MB."
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

    @Test("long clips go to the engine whole", arguments: [4, 8, 16, 20, 80])
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

    // MARK: Dictionary terms (the gate of ADR 0016)

    /// The name that Parakeet v3 writes as "Kyle Thorn" without help, and the sentences it is spoken in.
    private static let boostedTerm = "Kaelthorn"
    private static let boostedSentence = "Mañana tengo una reunión con Kaelthorn para revisar el contrato."
    private static let boostedOtherSentence = "Le escribí a Kaelthorn ayer por la tarde."
    /// About five seconds of Spanish with no dictionary term in it, and the dictionary that must leave it alone: a short
    /// brand that sounds like common words, a name with an accent, and the name of the other test.
    private static let plainSentence = "Hola, quería confirmar la reunión de mañana a las diez con el equipo de ventas."
    private static let bystanders = [boostedTerm, "Acme", "González"]

    /// A recognizer over the real engine whose CTC model has arrived. Reports how long the arrival took, which includes
    /// the download the first time.
    private static func boostedRecognizer() async -> (ParakeetRecognizer, Duration) {
        let booster = VocabularyBooster(load: { try await LiveBoostingModel.load(modelsRoot: Self.modelsRoot) })
        let recognizer = ParakeetRecognizer(engine: LiveParakeetEngine(booster: booster))
        var changes = await recognizer.readinessChanges().makeAsyncIterator()
        await recognizer.prepare()
        while let readiness = await changes.next(), readiness != .ready {}
        let started = ContinuousClock.now
        await booster.prepare()
        return (recognizer, ContinuousClock.now - started)
    }

    private static let modelsRoot = URL.applicationSupportDirectory.appending(
        path: "Susurro/Models", directoryHint: .isDirectory)

    private static func transcript(
        of samples: [Float], by recognizer: ParakeetRecognizer, boosting terms: [String] = []
    ) async throws -> (text: String, latency: Duration) {
        let started = ContinuousClock.now
        let text = try await recognizer.transcribe(
            AudioClip(samples: samples),
            options: RecognitionOptions(language: "es", vocabulary: terms, boostTerms: terms)
        ).text
        return (text, ContinuousClock.now - started)
    }

    @Test("the CTC model is in the app's folder, at the pinned commit")
    func boostModelIsPinned() async throws {
        _ = await Self.boostedRecognizer()

        let folder = LiveBoostingModel.directory(in: Self.modelsRoot)
        #expect(LiveBoostingModel.holdsPinnedRevision(at: folder))
        #expect(CtcModels.modelsExist(at: folder))
    }

    @Test("a dictionary term spoken in Spanish is written when it is boosted, and is not without it")
    func dictionaryTermIsRecovered() async throws {
        let (recognizer, loadTime) = await Self.boostedRecognizer()
        print("REAL-MODEL boost model ready in \(loadTime)")
        // Paulina and Mónica, each with and without a second and a half of silence before the speech, and a second
        // sentence for the last run.
        let runs: [(voice: String, lead: Double, sentence: String)] = [
            ("Paulina", 0, Self.boostedSentence), ("Paulina", 1.5, Self.boostedSentence),
            ("Mónica", 0, Self.boostedSentence), ("Mónica", 1.5, Self.boostedSentence),
            ("Paulina", 0, Self.boostedOtherSentence),
        ]

        var recovered = 0
        for run in runs {
            let speech = try Self.speak(run.sentence, voice: run.voice)
            let samples = [Float](repeating: 0, count: Int(run.lead * 16_000)) + speech
            let plain = try await Self.transcript(of: samples, by: recognizer).text
            let boosted = try await Self.transcript(of: samples, by: recognizer, boosting: [Self.boostedTerm]).text
            let success = boosted.contains(Self.boostedTerm) && !plain.contains(Self.boostedTerm)
            if success { recovered += 1 }
            print(
                "REAL-MODEL boost \(run.voice) lead \(run.lead) s: without \"\(plain)\"; with \"\(boosted)\"; \(success ? "recovered" : "NOT recovered")"
            )
        }
        print("REAL-MODEL boost recall: \(recovered) of \(runs.count)")

        #expect(recovered >= 4)
    }

    @Test("a dictionary that does not occur in the speech changes nothing")
    func noFalseReplacement() async throws {
        let (recognizer, _) = await Self.boostedRecognizer()

        var replaced = 0
        for voice in ["Paulina", "Mónica"] {
            let samples = try Self.speak(Self.plainSentence, voice: voice)
            let plain = try await Self.transcript(of: samples, by: recognizer).text
            let boosted = try await Self.transcript(of: samples, by: recognizer, boosting: Self.bystanders).text
            if boosted != plain { replaced += 1 }
            print("REAL-MODEL boost bystanders \(voice): without \"\(plain)\"; with \"\(boosted)\"")
            #expect(boosted == plain)
        }
        print("REAL-MODEL boost false replacements: \(replaced) of 2")
    }

    /// More sentences with no dictionary term in them, and two with a first name that sounds like a surname of the
    /// dictionary.
    private static let unrelatedSentences = [
        "El informe de ventas del trimestre está listo para revisión.",
        "Necesito que me envíes el contrato firmado antes del viernes.",
        "Vamos a cenar con los clientes en el restaurante de siempre.",
        "El equipo de soporte atendió doscientos tickets durante la última semana.",
        "Por favor, confirma la reunión con Carlos para el lunes a las nueve.",
    ]
    private static let lookalikeSentences = [
        "Ayer hablé con Gonzalo sobre el pedido de la semana pasada.",
        "Mi hermano Fernando llega mañana por la tarde desde Valparaíso.",
    ]
    private static let wideDictionary = ["Kaelthorn", "González", "Fernández", "Susurro", "Mapfre", "Acme Corp"]

    /// How many clips of `sentences` the dictionary changes, with the voices Paulina and Mónica.
    private static func replacements(
        in sentences: [String], by recognizer: ParakeetRecognizer
    ) async throws -> (replaced: Int, clips: Int) {
        var clips = 0
        var replaced = 0
        for sentence in sentences {
            for voice in ["Paulina", "Mónica"] {
                let samples = try speak(sentence, voice: voice)
                let plain = try await transcript(of: samples, by: recognizer).text
                let boosted = try await transcript(of: samples, by: recognizer, boosting: wideDictionary).text
                clips += 1
                if boosted != plain {
                    replaced += 1
                    print("REAL-MODEL boost REPLACED \(voice): without \"\(plain)\"; with \"\(boosted)\"")
                }
            }
        }
        return (replaced, clips)
    }

    @Test("a wider dictionary changes nothing in sentences that do not hold its terms")
    func unrelatedSentencesAreLeftAlone() async throws {
        let (recognizer, _) = await Self.boostedRecognizer()

        let unrelated = try await Self.replacements(in: Self.unrelatedSentences, by: recognizer)
        print("REAL-MODEL boost false replacements on unrelated sentences: \(unrelated.replaced) of \(unrelated.clips)")
        // A first name that sounds like a surname of the dictionary is the known limit of keyword spotting: the audio
        // fits the term about as well as the word that was said. It is measured and printed, not required to pass, so that
        // a new FluidAudio version shows in the numbers (ADR 0016).
        let lookalikes = try await Self.replacements(in: Self.lookalikeSentences, by: recognizer)
        print("REAL-MODEL boost lookalike names replaced: \(lookalikes.replaced) of \(lookalikes.clips)")

        #expect(unrelated.replaced == 0)
    }

    @Test("boosting adds under half a second to a clip of about five seconds")
    func boostingLatency() async throws {
        let (recognizer, _) = await Self.boostedRecognizer()
        let samples = try Self.speak(Self.plainSentence)
        let seconds = Double(samples.count) / 16_000
        // The first runs include warming up the models, so they are made and not counted.
        for _ in 0..<2 {
            _ = try await Self.transcript(of: samples, by: recognizer)
            _ = try await Self.transcript(of: samples, by: recognizer, boosting: Self.bystanders)
        }

        // Alternating the two kinds of run would time the switch between the models on the Neural Engine as well, which
        // a dictation does not pay when the next one is also a dictation with a dictionary.
        var plain: [Double] = []
        for _ in 0..<7 { plain.append(try await Self.transcript(of: samples, by: recognizer).latency.milliseconds) }
        var boosted: [Double] = []
        for _ in 0..<7 {
            boosted.append(
                try await Self.transcript(of: samples, by: recognizer, boosting: Self.bystanders).latency.milliseconds)
        }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        let added = median(boosted) - median(plain)
        print(
            "REAL-MODEL boost latency on \(seconds) s: without \(plain.map { Int($0) }) ms, with \(boosted.map { Int($0) }) ms; medians \(median(plain)) and \(median(boosted)) ms, added \(added) ms"
        )

        #expect(added < 500)
    }

    /// The numbers behind ADR 0031: what one partial over the trailing window costs, and how much later the transcript
    /// of a dictation comes back when the key goes up while a partial is inside the engine (the worst case, since a
    /// partial cannot be stopped once it runs).
    @Test("a partial over the window costs a fraction of a second, and delays a dictation by one partial at most")
    func partialLatency() async throws {
        let (recognizer, _, _) = await Self.loadedRecognizer()
        let speech = try Self.speak(Self.sentence + Self.sentence)
        let window = AudioClip(samples: Array(speech.suffix(12 * AudioClip.sampleRate)))
        let dictation = AudioClip(samples: speech)
        for _ in 0..<2 {
            _ = try await recognizer.transcribePartial(window, language: nil)
            _ = try await recognizer.transcribe(dictation, options: RecognitionOptions())
        }

        var partials: [Double] = []
        for _ in 0..<7 {
            let started = ContinuousClock.now
            _ = try #require(try await recognizer.transcribePartial(window, language: nil))
            partials.append((ContinuousClock.now - started).milliseconds)
        }
        var alone: [Double] = []
        var behind: [Double] = []
        for _ in 0..<7 {
            var started = ContinuousClock.now
            _ = try await recognizer.transcribe(dictation, options: RecognitionOptions())
            alone.append((ContinuousClock.now - started).milliseconds)
            let partial = Task { try await recognizer.transcribePartial(window, language: nil) }
            // The partial takes the turn first; the dictation then waits for it, as at a key-up during a partial.
            while await !recognizer.isTranscribing { await Task.yield() }
            started = ContinuousClock.now
            _ = try await recognizer.transcribe(dictation, options: RecognitionOptions())
            behind.append((ContinuousClock.now - started).milliseconds)
            _ = try await partial.value
        }
        let median = { (values: [Double]) in values.sorted()[values.count / 2] }
        let added = median(behind) - median(alone)
        print(
            "REAL-MODEL partial on \(window.duration): \(partials.map { Int($0) }) ms, median \(median(partials)) ms; dictation of \(dictation.duration) alone \(alone.map { Int($0) }) ms, behind a partial \(behind.map { Int($0) }) ms, added \(added) ms"
        )

        #expect(median(partials) < 500)
        #expect(added < 500)
    }

    @Test("Silero finds the speech between two seconds of silence, and nothing in silence alone")
    func sileroSegments() async throws {
        let speech = try Self.speak(Self.sentence)
        let silence = [Float](repeating: 0, count: 2 * AudioClip.sampleRate)
        let clip = AudioClip(samples: silence + speech + silence)
        let detector = SileroVADDetector()

        let found = try await detector.analyze(clip)
        let none = try await detector.analyze(AudioClip(samples: silence))
        print("REAL-MODEL silero: \(found.segments) in a clip of \(clip.duration), none: \(none.segments)")

        let first = try #require(found.segments.first)
        let last = try #require(found.segments.last)
        // The model decides in blocks of 256 ms, so the edges are only as exact as that.
        #expect(first.start > .seconds(1.5) && first.start < .seconds(2.6))
        #expect(last.end > .seconds(2) + AudioClip.duration(ofSamples: speech.count) - .seconds(0.6))
        #expect(none.segments.isEmpty)
    }
}

extension Duration {
    /// Milliseconds, for the numbers the checks print.
    fileprivate var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
