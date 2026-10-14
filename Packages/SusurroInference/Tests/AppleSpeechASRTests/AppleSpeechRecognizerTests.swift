import CoreTestSupport
import Domain
import Synchronization
import Testing

@testable import AppleSpeechASR

@Suite("Apple speech recognizer", .timeLimit(.minutes(1)))
struct AppleSpeechRecognizerTests {
    private struct Failure: Error {}

    private final class FakeEngine: AppleSpeechEngine {
        private let supported: Bool
        private let installFailure: (any Error)?
        private let transcript: Result<String, any Error>
        private let installGate: Gate?
        private let calls = Mutex<[String]>([])
        private let languages = Mutex<[String]>([])

        init(
            supported: Bool = true, installFailure: (any Error)? = nil,
            transcript: Result<String, any Error> = .success("hola"),
            gatedInstall: Bool = false
        ) {
            self.supported = supported
            self.installFailure = installFailure
            self.transcript = transcript
            installGate = gatedInstall ? Gate() : nil
        }

        var installs: Int { calls.withLock { $0.filter { $0 == "install" }.count } }
        var transcribedLanguages: [String] { languages.withLock { $0 } }
        func releaseInstall() { installGate?.open() }

        func isSupported(language: String) async -> Bool { supported }

        func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws {
            calls.withLock { $0.append("install") }
            progress(0.5)
            await installGate?.wait()
            if let installFailure { throw installFailure }
        }

        func transcribe(_ samples: [Float], language: String) async throws -> String {
            languages.withLock { $0.append(language) }
            return try transcript.get()
        }
    }

    private static let clip = AudioClip(samples: [Float](repeating: 0.1, count: 16_000))

    /// Waits until the recognizer says something other than loading, polling its readiness.
    private static func settled(_ recognizer: AppleSpeechRecognizer) async -> RecognizerReadiness {
        for _ in 0..<2_000 {
            let readiness = await recognizer.readiness()
            if case .loading = readiness {} else { return readiness }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await recognizer.readiness()
    }

    @Test("the recognizer names itself, runs on this Mac, and has no clip limit")
    func identity() {
        let recognizer = AppleSpeechRecognizer(engine: FakeEngine())

        #expect(recognizer.id == ASRProviderID("apple-speech"))
        #expect(recognizer.locality == .local)
        #expect(recognizer.maxClipDuration == nil)
    }

    @Test("it reads as loading until the language is installed, then ready")
    func prepares() async {
        let engine = FakeEngine()
        let recognizer = AppleSpeechRecognizer(engine: engine)

        #expect(await recognizer.readiness() == .loading(progress: 0))
        await recognizer.prepare()
        #expect(await Self.settled(recognizer) == .ready)
        await recognizer.prepare()
        #expect(engine.installs == 1)
    }

    @Test("progress of the install is reported while it runs, and never reaches ready by itself")
    func progress() async {
        let engine = FakeEngine(gatedInstall: true)
        let recognizer = AppleSpeechRecognizer(engine: engine)
        await recognizer.prepare()
        for _ in 0..<2_000 {
            if await recognizer.readiness() == .loading(progress: 0.5) { break }
            try? await Task.sleep(for: .milliseconds(1))
        }

        #expect(await recognizer.readiness() == .loading(progress: 0.5))
        engine.releaseInstall()
        #expect(await Self.settled(recognizer) == .ready)
    }

    @Test("a Mac that cannot transcribe the language is unavailable for good")
    func unsupported() async {
        let recognizer = AppleSpeechRecognizer(engine: FakeEngine(supported: false))
        await recognizer.prepare()

        if case .unavailable(_, let retryable) = await Self.settled(recognizer) {
            #expect(!retryable)
        } else {
            Issue.record("not unavailable")
        }
    }

    @Test("an install that fails can be tried again")
    func installFailure() async {
        let recognizer = AppleSpeechRecognizer(engine: FakeEngine(installFailure: Failure()))
        await recognizer.prepare()

        if case .unavailable(_, let retryable) = await Self.settled(recognizer) {
            #expect(retryable)
        } else {
            Issue.record("not unavailable")
        }
    }

    @Test("transcribing asks the engine for the language, or the prepared one when none is pinned")
    func transcribes() async throws {
        let engine = FakeEngine(transcript: .success("buenos días"))
        let recognizer = AppleSpeechRecognizer(engine: engine)
        await recognizer.prepare()
        _ = await Self.settled(recognizer)

        let pinned = try await recognizer.transcribe(Self.clip, options: RecognitionOptions(language: "es-CL"))
        _ = try await recognizer.transcribe(Self.clip, options: RecognitionOptions())

        #expect(pinned.text == "buenos días")
        #expect(engine.transcribedLanguages == ["es-CL", "es"])
    }

    @Test("transcribing before the language is ready refuses")
    func notReady() async {
        let recognizer = AppleSpeechRecognizer(engine: FakeEngine())

        await #expect(throws: RecognitionError.notReady) {
            try await recognizer.transcribe(Self.clip, options: RecognitionOptions())
        }
    }

    @Test("an engine failure is an engine error, and a cancellation stays one")
    func failures() async {
        let failing = AppleSpeechRecognizer(engine: FakeEngine(transcript: .failure(Failure())))
        let cancelled = AppleSpeechRecognizer(engine: FakeEngine(transcript: .failure(CancellationError())))
        for recognizer in [failing, cancelled] {
            await recognizer.prepare()
            _ = await Self.settled(recognizer)
        }

        await #expect(throws: RecognitionError.engineFailed(String(describing: Failure()))) {
            try await failing.transcribe(Self.clip, options: RecognitionOptions())
        }
        await #expect(throws: CancellationError.self) {
            try await cancelled.transcribe(Self.clip, options: RecognitionOptions())
        }
    }
}
