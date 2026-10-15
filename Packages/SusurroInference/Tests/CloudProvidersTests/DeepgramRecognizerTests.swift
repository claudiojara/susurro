import CoreTestSupport
import Domain
import Foundation
import InferenceTestSupport
import Testing

@testable import CloudProviders

@Suite("Deepgram recognizer", .timeLimit(.minutes(1)))
struct DeepgramRecognizerTests {
    private static let key = "dg-sentinel-key-0123456789"
    private static let reply = #"{"results":{"channels":[{"alternatives":[{"transcript":"hola equipo"}]}]}}"#
    private let clip = AudioClip(samples: (0..<1_600).map { Float($0 % 100) / 200 })

    private struct Rig {
        let server: StubServer
        let settings = InMemorySettingsStore()
        let secrets: InMemorySecretStore
        let log = RecordingDiagnostics()
        let recognizer: DeepgramRecognizer

        init(
            enabled: Bool = true, key: String? = DeepgramRecognizerTests.key,
            reply: StubReply = .json(DeepgramRecognizerTests.reply)
        ) {
            server = StubServer(reply: reply)
            secrets = InMemorySecretStore(key.map { [.deepgram: $0] } ?? [:])
            settings.set(enabled, for: SpeechSettings.deepgramEnabled)
            recognizer = DeepgramRecognizer(
                settings: settings, secrets: secrets, session: server.session, endpoint: server.url("/v1/listen"),
                diagnostics: log)
        }
    }

    // MARK: Identity and readiness

    @Test("it is the cloud provider deepgram, with no clip limit")
    func identity() {
        let rig = Rig()
        #expect(rig.recognizer.id == ASRProviderID("deepgram"))
        #expect(rig.recognizer.locality == .cloud)
        #expect(rig.recognizer.maxClipDuration == nil)
    }

    @Test("it is unusable until it is turned on and a key exists, and it says what is missing")
    func readiness() async {
        let off = await Rig(enabled: false).recognizer.readiness()
        let noKey = await Rig(enabled: true, key: nil).recognizer.readiness()
        let ready = await Rig().recognizer.readiness()

        guard case .unavailable(let offReason, false) = off else { Issue.record("off was \(off)"); return }
        guard case .unavailable(let keyReason, false) = noKey else { Issue.record("no key was \(noKey)"); return }
        #expect(offReason.contains("off"))
        #expect(keyReason.contains("Keychain") && keyReason.contains("deepgram"))
        #expect(ready == .ready)
    }

    @Test("readiness never touches the network, and never reads the key")
    func readinessIsLocal() async {
        let rig = Rig()
        _ = await rig.recognizer.readiness()
        #expect(rig.server.requests.isEmpty)
        #expect(rig.secrets.readCount(of: .deepgram) == 0)
    }

    @Test("with the default settings no audio is sent, whatever is asked")
    func defaultSendsNothing() async {
        let server = StubServer(reply: .json(Self.reply))
        let recognizer = DeepgramRecognizer(
            settings: InMemorySettingsStore(), secrets: InMemorySecretStore([.deepgram: Self.key]),
            session: server.session, endpoint: server.url("/v1/listen"))

        await #expect(throws: RecognitionError.notReady) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(server.requests.isEmpty)
    }

    @Test("turned on without a key, nothing is sent either")
    func enabledWithoutKey() async {
        let rig = Rig(enabled: true, key: nil)

        await #expect(throws: RecognitionError.notReady) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(rig.server.requests.isEmpty)
    }

    @Test("behind the session cache, N dictations read the Keychain exactly once, and every one sends the key")
    func sessionCacheReadsOnce() async throws {
        let rig = Rig()
        let recognizer = DeepgramRecognizer(
            settings: rig.settings, secrets: SessionSecretCache(rig.secrets), session: rig.server.session,
            endpoint: rig.server.url("/v1/listen"))

        for _ in 0..<5 {
            _ = await recognizer.readiness()
            _ = try await recognizer.transcribe(clip, options: RecognitionOptions())
        }

        #expect(rig.secrets.readCount(of: .deepgram) == 1)
        #expect(rig.server.requests.count == 5)
        #expect(rig.server.requests.allSatisfy { $0.headers["Authorization"] == "Token \(Self.key)" })
    }

    // MARK: The request

    @Test("the key is in the Authorization header, never in the address, and the body is the audio as a WAV")
    func requestShape() async throws {
        let rig = Rig()

        let transcript = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(transcript == RawTranscript(text: "hola equipo"))
        let request = try #require(rig.server.requests.first)
        #expect(rig.server.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.header("Authorization") == "Token \(Self.key)")
        #expect(request.header("Content-Type") == "audio/wav")
        #expect(request.body == clip.wavData())
        #expect(!request.url.absoluteString.contains(Self.key))
        #expect(request.url.host == rig.server.host)
        #expect(request.url.path == "/v1/listen")
    }

    @Test("the key is read for each request, and not kept")
    func keyIsReadEveryTime() async throws {
        let rig = Rig()

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        rig.secrets.set("rotated-key", for: .deepgram)
        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(rig.server.requests.map { $0.header("Authorization") } == ["Token \(Self.key)", "Token rotated-key"])
    }

    @Test("automatic language asks Deepgram to detect it, and a pinned language is passed as it is")
    func language() async throws {
        let rig = Rig()

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions(language: nil))
        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions(language: "es"))

        let queries = rig.server.requests.map(\.query)
        #expect(queries[0].contains(URLQueryItem(name: "detect_language", value: "true")))
        #expect(!queries[0].contains { $0.name == "language" })
        #expect(queries[1].contains(URLQueryItem(name: "language", value: "es")))
        #expect(!queries[1].contains { $0.name == "detect_language" })
    }

    @Test("the vocabulary goes as key terms, one parameter each, and special characters survive")
    func vocabulary() async throws {
        let rig = Rig()
        let terms = ["Acme", "Maria Gonzalez", "C++", "R&D"]

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions(vocabulary: terms))

        let request = try #require(rig.server.requests.first)
        #expect(request.query.filter { $0.name == "keyterm" }.compactMap(\.value) == terms)
        #expect(request.url.absoluteString.contains("keyterm=Maria%20Gonzalez"))
        #expect(request.url.absoluteString.contains("keyterm=C%2B%2B"))
        #expect(request.url.absoluteString.contains("keyterm=R%26D"))
    }

    @Test("no more key terms than the limit are sent")
    func vocabularyLimit() async throws {
        let rig = Rig()
        let terms = (0..<300).map { "term\($0)" }

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions(vocabulary: terms))

        let request = try #require(rig.server.requests.first)
        #expect(request.query.filter { $0.name == "keyterm" }.count == DeepgramRecognizer.keyTermLimit)
    }

    @Test("nothing but the model, the language, the formatting, and the vocabulary is sent with the audio")
    func noContextFields() async throws {
        let rig = Rig()

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions(language: "es", vocabulary: ["Acme"]))

        let request = try #require(rig.server.requests.first)
        let names = Set(request.query.map(\.name))
        #expect(names.isSubset(of: ["model", "language", "detect_language", "smart_format", "keyterm"]))
        #expect(
            Set(request.headers.keys.map { $0.lowercased() }).isSubset(of: [
                "authorization", "content-type", "content-length", "accept", "accept-encoding", "accept-language",
                "user-agent",
            ]))
    }

    // MARK: Failure

    @Test("an HTTP error throws, and the error and the log say only the status, never the key")
    func httpError() async {
        let rig = Rig(reply: .json(#"{"err":"bad key \#(Self.key)"}"#, status: 401))

        await #expect(throws: RecognitionError.engineFailed("Deepgram: http-401")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(rig.log.events == [.cloudRequestFailed(provider: "deepgram", reason: "http-401")])
        #expect(!String(describing: rig.log.events).contains(Self.key))
    }

    @Test("a timeout throws as a timeout")
    func timeout() async {
        let rig = Rig(reply: .failure(.timedOut))

        await #expect(throws: RecognitionError.engineFailed("Deepgram: timeout")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(rig.log.events == [.cloudRequestFailed(provider: "deepgram", reason: "timeout")])
    }

    @Test("a dead network throws")
    func network() async {
        let rig = Rig(reply: .failure(.notConnectedToInternet))

        await #expect(throws: RecognitionError.engineFailed("Deepgram: network")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("an answer that is not a transcript throws")
    func malformedAnswer() async {
        let rig = Rig(reply: .json(#"{"nothing":true}"#))

        await #expect(throws: RecognitionError.engineFailed("Deepgram: response")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("an empty transcript is returned as it is, for the pipeline to end as no-speech")
    func emptyTranscript() async throws {
        let rig = Rig(reply: .json(#"{"results":{"channels":[{"alternatives":[{"transcript":""}]}]}}"#))

        #expect(try await rig.recognizer.transcribe(clip, options: RecognitionOptions()).text == "")
    }

    @Test("cancelling the task cancels the request and throws a cancellation")
    func cancellation() async throws {
        let rig = Rig(reply: .hang)
        let task = Task { try await rig.recognizer.transcribe(clip, options: RecognitionOptions()) }
        while rig.server.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(rig.log.events.isEmpty)
    }
}
