import CoreTestSupport
import Darwin
import Domain
import Foundation
import LocalWhisper
import Testing

/// Local Whisper against a real whisper.cpp install on this Mac: its server over HTTP, and its command line tool behind
/// a wrapper script. Nothing is installed or downloaded: a test is skipped when `whisper-server`, `whisper-cli`, or a
/// model file is not already there. The model is the first of `SUSURRO_WHISPER_MODEL` and the `ggml-*.bin` files in
/// `~/.local/share/whisper-cpp/models`.
@Suite("Real whisper.cpp through Local Whisper", .realModels, .serialized, .timeLimit(.minutes(10)))
struct RealLocalWhisperTests {
    private static let sentence = "Hola, quería confirmar la reunión de mañana a las diez con el equipo de ventas."

    private struct Install {
        let server: URL
        let cli: URL
        let model: URL
    }

    private static func install() throws -> Install {
        func tool(_ name: String) -> URL? {
            ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(filePath: $0).appending(path: name) }
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        let folder = URL.homeDirectory.appending(path: ".local/share/whisper-cpp/models")
        let listed =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("ggml-") && !$0.lastPathComponent.contains("silero") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        let fromEnvironment = ProcessInfo.processInfo.environment["SUSURRO_WHISPER_MODEL"].map {
            URL(filePath: $0)
        }
        guard let server = tool("whisper-server"), let cli = tool("whisper-cli"),
            let model = fromEnvironment ?? listed.first
        else {
            try Test.cancel("whisper.cpp (whisper-server, whisper-cli, and a ggml model) is not installed.")
        }
        return Install(server: server, cli: cli, model: model)
    }

    /// A TCP port that nothing listens on now.
    private static func freePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        try #require(named == 0)
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func clip(_ text: String) throws -> AudioClip {
        let speech = try SpokenClip.speak(text)
        return AudioClip(samples: SpokenClip.silence(seconds: 0.3) + speech + SpokenClip.silence(seconds: 0.3))
    }

    // MARK: The server

    @Test("a whisper.cpp server on localhost: not installed before it runs, ready and transcribing once it does")
    func server() async throws {
        let install = try Self.install()
        let port = try Self.freePort()
        let settings = InMemorySettingsStore()
        settings.set(LocalWhisperMode.http, for: SpeechSettings.localWhisperMode)
        settings.set(LocalWhisperServerStyle.whisperCpp, for: SpeechSettings.localWhisperServerStyle)
        settings.set("http://127.0.0.1:\(port)/inference", for: SpeechSettings.localWhisperEndpoint)
        let recognizer = LocalWhisperRecognizer(settings: settings)
        let spoken = try Self.clip(Self.sentence)

        let before = await recognizer.readiness()
        print("REAL-WORLD 9f.11 http before the server runs: readiness \(before)")
        #expect(before == .notInstalled)

        // `-l auto` is how a user lets the app leave the language to the server; the pinned case sends it.
        let process = Process()
        process.executableURL = install.server
        process.arguments = ["-m", install.model.path, "--host", "127.0.0.1", "--port", "\(port)", "-l", "auto"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }

        let started = ContinuousClock.now
        var readiness = RecognizerReadiness.notInstalled
        while ContinuousClock.now - started < .seconds(120) {
            readiness = await recognizer.readiness()
            if readiness == .ready || !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        print(
            "REAL-WORLD 9f.11 http \(install.model.lastPathComponent) on port \(port): readiness \(readiness) after \(ContinuousClock.now - started)"
        )
        try #require(readiness == .ready)

        for (label, language) in [("language pinned to es", "es"), ("language left to the server (-l auto)", nil)] {
            let asked = ContinuousClock.now
            let transcript = try await recognizer.transcribe(spoken, options: RecognitionOptions(language: language))
            let took = ContinuousClock.now - asked
            print(
                "REAL-WORLD 9f.11 http \(label): \"\(transcript.text)\" in \(took) for \(SpokenClip.seconds(spoken.samples)) s of audio"
            )
            let words = SpokenClip.words(transcript.text)
            #expect(words.contains("reunion") && words.contains("ventas"))
        }

        // A server that stops answering is `notInstalled` again, and a transcription fails with an error the pipeline
        // keeps the audio for.
        process.terminate()
        process.waitUntilExit()
        #expect(await recognizer.readiness() == .notInstalled)
        await #expect(throws: RecognitionError.self) {
            try await recognizer.transcribe(spoken, options: RecognitionOptions(language: "es"))
        }
    }

    // MARK: The command line tool

    @Test(
        "a wrapper script around whisper-cli: ready, transcribing with the pinned language, and not installed when gone"
    )
    func commandLine() async throws {
        let install = try Self.install()
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "susurro-whisper-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The tool is called as `<path> <wav file>` and the language is in SUSURRO_LANGUAGE (auto when it is not set).
        let wrapper = folder.appending(path: "whisper-wrapper.sh")
        let script = """
            #!/bin/sh
            exec '\(install.cli.path)' -m '\(install.model.path)' -l "${SUSURRO_LANGUAGE:-auto}" -nt -np -f "$1"
            """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)

        let settings = InMemorySettingsStore()
        settings.set(LocalWhisperMode.cli, for: SpeechSettings.localWhisperMode)
        settings.set(wrapper.path, for: SpeechSettings.localWhisperExecutable)
        let recognizer = LocalWhisperRecognizer(settings: settings, timeout: .seconds(120))
        let spoken = try Self.clip(Self.sentence)

        let ready = await recognizer.readiness()
        print("REAL-WORLD 9f.11 cli readiness with the wrapper: \(ready)")
        #expect(ready == .ready)

        for (label, language) in [("language pinned to es", "es"), ("language auto", nil)] {
            let asked = ContinuousClock.now
            let transcript = try await recognizer.transcribe(spoken, options: RecognitionOptions(language: language))
            let took = ContinuousClock.now - asked
            print(
                "REAL-WORLD 9f.11 cli \(label): \"\(transcript.text)\" in \(took) for \(SpokenClip.seconds(spoken.samples)) s of audio"
            )
            let words = SpokenClip.words(transcript.text)
            #expect(words.contains("reunion") && words.contains("ventas"))
        }

        try FileManager.default.removeItem(at: wrapper)
        #expect(await recognizer.readiness() == .notInstalled)
    }
}
