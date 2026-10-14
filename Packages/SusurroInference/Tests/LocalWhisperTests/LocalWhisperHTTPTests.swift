import CoreTestSupport
import Domain
import Foundation
import InferenceTestSupport
import Testing

@testable import LocalWhisper

@Suite("Local Whisper server", .timeLimit(.minutes(1)))
struct LocalWhisperHTTPTests {
    private let clip = AudioClip(samples: (0..<800).map { Float($0 % 50) / 100 })

    /// A recognizer in `http` mode whose address is the stub, which the rule of the address is told to accept.
    private struct Rig {
        let server: StubServer
        let settings: InMemorySettingsStore
        let recognizer: LocalWhisperRecognizer

        init(
            reply: StubReply = .json(#"{"text":" hola equipo "}"#), path: String = "/v1/audio/transcriptions",
            style: LocalWhisperServerStyle = .openAICompatible, model: String = "", allowAnyHost: Bool = true
        ) {
            let server = StubServer(reply: reply)
            let settings = InMemorySettingsStore()
            settings.set(server.url(path).absoluteString, for: SpeechSettings.localWhisperEndpoint)
            settings.set(style, for: SpeechSettings.localWhisperServerStyle)
            settings.set(model, for: SpeechSettings.localWhisperModel)
            let host = server.host
            let isAllowed: @Sendable (URL) -> Bool
            if allowAnyHost {
                isAllowed = { $0.host == host }
            } else {
                isAllowed = { LoopbackEndpoint.validated($0.absoluteString) != nil }
            }
            self.server = server
            self.settings = settings
            recognizer = LocalWhisperRecognizer(
                settings: settings, session: server.session, isAllowedEndpoint: isAllowed)
        }
    }

    // MARK: Identity

    @Test("it is the local provider local-whisper")
    func identity() {
        let recognizer = LocalWhisperRecognizer(settings: InMemorySettingsStore())
        #expect(recognizer.id == ASRProviderID("local-whisper"))
        #expect(recognizer.locality == .local)
    }

    // MARK: The request

    @Test(
        "an OpenAI-compatible server gets the WAV as a multipart file with the model, the language, and the vocabulary as the prompt"
    )
    func openAIRequest() async throws {
        let rig = Rig(model: "large-v3")

        let transcript = try await rig.recognizer.transcribe(
            clip, options: RecognitionOptions(language: "es", vocabulary: ["Acme", "Maria Gonzalez"]))

        #expect(transcript == RawTranscript(text: "hola equipo"))
        let request = try #require(rig.server.requests.first)
        #expect(rig.server.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.url.path == "/v1/audio/transcriptions")
        #expect(request.header("Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let text = request.bodyText
        #expect(text.contains(#"name="file"; filename="audio.wav""#))
        #expect(text.contains("Content-Type: audio/wav"))
        #expect(request.body.range(of: clip.wavData()) != nil, "the body does not hold the audio as a WAV")
        #expect(text.contains("name=\"model\"\r\n\r\nlarge-v3\r\n"))
        #expect(text.contains("name=\"language\"\r\n\r\nes\r\n"))
        #expect(text.contains("name=\"prompt\"\r\n\r\nAcme, Maria Gonzalez\r\n"))
        #expect(text.contains("name=\"response_format\"\r\n\r\njson\r\n"))
    }

    @Test("a whisper.cpp server style sends no model, and no language or prompt when there are none")
    func whisperCppRequest() async throws {
        let rig = Rig(path: "/inference", style: .whisperCpp, model: "ignored")

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())

        let text = try #require(rig.server.requests.first).bodyText
        #expect(rig.server.requests.first?.url.path == "/inference")
        #expect(!text.contains(#"name="model""#))
        #expect(!text.contains(#"name="language""#))
        #expect(!text.contains(#"name="prompt""#))
        #expect(text.contains(#"name="file""#))
    }

    @Test("an OpenAI-compatible server with no model set is sent none")
    func noModel() async throws {
        let rig = Rig()

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(!(rig.server.requests.first?.bodyText.contains(#"name="model""#) ?? true))
    }

    @Test("no key, header, or cookie of any kind is sent: the server is on this Mac and needs none")
    func noCredentials() async throws {
        let rig = Rig()

        _ = try await rig.recognizer.transcribe(clip, options: RecognitionOptions())

        let headers = Set(try #require(rig.server.requests.first).headers.keys.map { $0.lowercased() })
        #expect(!headers.contains("authorization"))
        #expect(!headers.contains("cookie"))
    }

    // MARK: The address

    @Test(
        "an address that is not on this Mac is refused before anything is sent",
        arguments: [
            "https://api.example.com/v1/audio/transcriptions", "http://192.168.1.20:8080/inference",
            "http://localhost.example.com/inference", "ftp://localhost/inference", "not an address", "",
        ])
    func nonLoopback(address: String) async {
        let server = StubServer()
        let settings = InMemorySettingsStore()
        settings.set(address, for: SpeechSettings.localWhisperEndpoint)
        let recognizer = LocalWhisperRecognizer(settings: settings, session: server.session)

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: the address must be on this Mac")) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(server.requests.isEmpty)
    }

    @Test("the real rule of the address, with no override, refuses a host that only looks like this Mac")
    func realRuleRefusesTheStub() async {
        let rig = Rig(allowAnyHost: false)

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: the address must be on this Mac")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(rig.server.requests.isEmpty)
    }

    @Test("a redirect to another host is refused, so the server cannot pass the audio on")
    func redirects() async {
        let elsewhere = StubServer()
        let rig = Rig(reply: .redirect(elsewhere.url("/steal")))

        await #expect(throws: (any Error).self) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(elsewhere.requests.isEmpty, "the audio followed a redirect to another host")
    }

    // MARK: The answer

    @Test("an error status is an error that names the status")
    func httpError() async {
        let rig = Rig(reply: .json(#"{"error":"model not loaded"}"#, status: 500))

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: http-500")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("an answer that is not a transcript is an error")
    func malformed() async {
        let rig = Rig(reply: .json(#"{"nothing":1}"#))

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: response")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("a timeout is an error")
    func timeout() async {
        let rig = Rig(reply: .failure(.timedOut))

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: timeout")) {
            try await rig.recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("cancelling the task cancels the request of the session")
    func cancellation() async throws {
        let rig = Rig(reply: .hang)
        let task = Task { try await rig.recognizer.transcribe(clip, options: RecognitionOptions()) }
        #expect(await eventually { !rig.server.requests.isEmpty })

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await eventually { rig.server.stoppedCount >= 1 }, "the request of the session was not cancelled")
    }

    // MARK: Readiness

    @Test("it is ready when the server answers, whatever the status")
    func readyWhenItAnswers() async {
        for reply in [StubReply.json("{}"), .json("", status: 405), .json("", status: 404)] {
            let rig = Rig(reply: reply)
            #expect(await rig.recognizer.readiness() == .ready)
            #expect(rig.server.requests.first?.method == "GET")
        }
    }

    @Test("it is not installed when nothing answers")
    func notInstalled() async {
        #expect(await Rig(reply: .failure(.cannotConnectToHost)).recognizer.readiness() == .notInstalled)
    }

    @Test("an address off this Mac is unavailable, with the reason, and nothing is sent")
    func readinessOfARemoteAddress() async {
        let rig = Rig(allowAnyHost: false)

        let readiness = await rig.recognizer.readiness()

        guard case .unavailable(let reason, false) = readiness else { Issue.record("was \(readiness)"); return }
        #expect(reason.contains("on this Mac"))
        #expect(rig.server.requests.isEmpty)
    }
}

@Suite("Local Whisper recognizer in command line mode", .timeLimit(.minutes(1)))
struct LocalWhisperRecognizerCommandTests {
    private let clip = AudioClip(samples: (0..<800).map { Float($0 % 50) / 100 })

    private func recognizer(
        tool: String, folder: ToolFolder, language: SpeechLanguage = .auto
    ) -> (LocalWhisperRecognizer, InMemorySettingsStore) {
        let settings = InMemorySettingsStore()
        settings.set(.cli, for: SpeechSettings.localWhisperMode)
        settings.set(tool, for: SpeechSettings.localWhisperExecutable)
        return (LocalWhisperRecognizer(settings: settings, temporaryDirectory: folder.url), settings)
    }

    @Test("the tool gets a file that holds the WAV, which is gone when the run is over")
    func temporaryFile() async throws {
        let folder = ToolFolder()
        let tool = folder.script("read.sh", "printf 'bytes=%s' \"$(wc -c < \"$1\" | tr -d ' ')\"")
        let (recognizer, _) = recognizer(tool: tool, folder: folder)

        let transcript = try await recognizer.transcribe(clip, options: RecognitionOptions())

        #expect(transcript.text == "bytes=\(clip.wavData().count)")
        #expect(folder.contents.filter { $0.hasSuffix(".wav") }.isEmpty, "the temporary file is still there")
    }

    @Test("the file is removed when the run fails too")
    func temporaryFileAfterFailure() async throws {
        let folder = ToolFolder()
        let tool = folder.script("fail.sh", "exit 1")
        let (recognizer, _) = recognizer(tool: tool, folder: folder)

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: exit 1")) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
        #expect(folder.contents.filter { $0.hasSuffix(".wav") }.isEmpty)
    }

    @Test("a bad path is an error that names the command, and nothing is run")
    func badPath() async {
        let folder = ToolFolder()
        let (recognizer, _) = recognizer(tool: "whisper", folder: folder)

        await #expect(throws: RecognitionError.engineFailed("Local Whisper: the command cannot be run")) {
            try await recognizer.transcribe(clip, options: RecognitionOptions())
        }
    }

    @Test("it is ready when the command can be run, and says why when it cannot")
    func readiness() async {
        let folder = ToolFolder()
        let good = folder.script("ok.sh", "echo hi")
        let plain = folder.script("plain.sh", "echo hi", executable: false)

        #expect(await recognizer(tool: good, folder: folder).0.readiness() == .ready)
        #expect(await recognizer(tool: "", folder: folder).0.readiness() == .notInstalled)
        #expect(await recognizer(tool: "/definitely/not/here", folder: folder).0.readiness() == .notInstalled)
        if case .unavailable(_, false) = await recognizer(tool: "whisper", folder: folder).0.readiness() {
        } else {
            Issue.record("a relative path should be unavailable")
        }
        if case .unavailable(_, false) = await recognizer(tool: plain, folder: folder).0.readiness() {
        } else {
            Issue.record("a file that cannot be run should be unavailable")
        }
    }
}
