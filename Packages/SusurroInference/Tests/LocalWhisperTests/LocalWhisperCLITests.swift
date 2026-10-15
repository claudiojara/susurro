import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import LocalWhisper

/// The threat matrix of the subprocess: what an argument can do, which paths are run, and how a run ends.
@Suite("Local Whisper command line tool", .serialized, .timeLimit(.minutes(1)))
struct LocalWhisperCLITests {
    private let tools = FakeTools.shared

    // MARK: Arguments

    @Test("the path of the file is passed as one argument, whatever characters it has, and no shell reads it")
    func hostilePaths() async throws {
        let folder = ToolFolder()
        defer { folder.remove() }
        let trap = folder.path("pwned")
        let paths = [
            "/tmp/with space/a b.wav", "/tmp/x; touch \(trap).wav", "/tmp/$(touch \(trap)).wav",
            "/tmp/`touch \(trap)`.wav", "/tmp/it's \"quoted\".wav", "/tmp/a | b && c > d.wav", "/tmp/-rf.wav",
            "/tmp/new\nline.wav",
        ]

        for path in paths {
            let output = try await LocalWhisperCLI(path: tools.echo).transcribe(wavPath: path, language: nil)

            #expect(output.hasPrefix("argc=1\narg=\(path)\n"), "the path \(path) was not passed as one argument")
        }
        #expect(!FileManager.default.fileExists(atPath: trap), "a command in a file name was run")
        #expect(!folder.contents.contains { $0.hasPrefix("pwned") })
    }

    @Test("the arguments are the path and nothing else")
    func argumentList() {
        #expect(LocalWhisperCLI.arguments(wavPath: "/tmp/a b.wav") == ["/tmp/a b.wav"])
    }

    @Test("a pinned language is in the environment of the tool, and none when it is automatic")
    func language() async throws {
        let pinned = try await LocalWhisperCLI(path: tools.echo).transcribe(wavPath: "/tmp/a.wav", language: "es")
        let automatic = try await LocalWhisperCLI(path: tools.echo).transcribe(wavPath: "/tmp/a.wav", language: nil)

        #expect(pinned.hasSuffix("language=es"))
        #expect(automatic.hasSuffix("language="))
    }

    @Test("what the tool prints is the transcript, trimmed")
    func transcript() async throws {
        #expect(
            try await LocalWhisperCLI(path: tools.say).transcribe(wavPath: "/tmp/a.wav", language: nil)
                == "hola equipo")
    }

    // MARK: Which paths are run

    @Test("a relative, missing, or not executable path is refused as an invalid executable")
    func invalidExecutable() throws {
        let cases: [(String, ExecutablePath.Problem)] = [
            ("whisper", .notAbsolute), ("./whisper", .notAbsolute), ("../bin/whisper", .notAbsolute),
            ("/definitely/not/here", .missing), (FileManager.default.temporaryDirectory.path, .missing),
            (tools.notExecutable, .notExecutable), ("", .empty),
        ]

        for (path, problem) in cases {
            #expect(throws: LocalWhisperError.invalidExecutable(problem), "the path \(path)") {
                try LocalWhisperCLI(path: path)
            }
        }
    }

    // MARK: How a run ends

    /// The id of the process that a `slow` tool started, once it has written it.
    private func processID(in file: String) async throws -> Int32 {
        // The file exists as soon as the shell opens it, and has the id a moment later.
        func read() -> Int32? {
            (try? String(contentsOfFile: file, encoding: .utf8)).flatMap {
                Int32($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        #expect(await eventually { read() != nil })
        return try #require(read())
    }

    @Test("a tool that runs past the limit is killed, and the run fails as a timeout")
    func timeout() async throws {
        let folder = ToolFolder()
        defer { folder.remove() }
        let pidFile = folder.path("pid")
        let clock = ManualClock()
        let cli = try LocalWhisperCLI(
            path: tools.slow, timeout: .seconds(60), clock: clock, environment: environment(["PIDFILE": pidFile]))
        let before = clock.suspendedSleeps

        let run = Task { try await cli.transcribe(wavPath: "/tmp/a.wav", language: nil) }
        await clock.waitForSleeps(before + 1)
        let pid = try await processID(in: pidFile)
        #expect(isAlive(pid: pid))

        clock.advance(by: .seconds(59))
        #expect(isAlive(pid: pid), "the tool was killed before the limit")
        clock.advance(by: .seconds(1))

        await #expect(throws: LocalWhisperError.timedOut) { try await run.value }
        #expect(await eventually { !isAlive(pid: pid) }, "the tool is still running after the limit")
    }

    @Test("cancelling the task kills the tool")
    func cancellation() async throws {
        let folder = ToolFolder()
        defer { folder.remove() }
        let pidFile = folder.path("pid")
        let clock = ManualClock()
        let cli = try LocalWhisperCLI(path: tools.slow, clock: clock, environment: environment(["PIDFILE": pidFile]))
        let before = clock.suspendedSleeps

        let run = Task { try await cli.transcribe(wavPath: "/tmp/a.wav", language: nil) }
        await clock.waitForSleeps(before + 1)
        let pid = try await processID(in: pidFile)

        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await eventually { !isAlive(pid: pid) }, "the tool is still running after the cancel")
    }

    @Test("a tool that exits with an error status is an error that names the status and not the output")
    func nonZeroExit() async throws {
        await #expect(throws: LocalWhisperError.failed(status: 3)) {
            try await LocalWhisperCLI(path: tools.failWithThree).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
        #expect(LocalWhisperError.failed(status: 3).recognitionError == .engineFailed("Local Whisper: exit 3"))
    }

    @Test("a tool that prints nothing, or only blanks, is an error")
    func emptyOutput() async throws {
        for tool in [tools.silent, tools.blanks] {
            await #expect(throws: LocalWhisperError.emptyOutput) {
                try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil)
            }
        }
    }

    @Test("a tool that prints more than the limit is killed and the run fails")
    func tooMuchOutput() async throws {
        await #expect(throws: LocalWhisperError.outputTooLarge) {
            try await LocalWhisperCLI(path: tools.flood).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
    }

    @Test("the tool has no input, so one that reads it does not wait")
    func noInput() async throws {
        #expect(
            try await LocalWhisperCLI(path: tools.readsInput).transcribe(wavPath: "/tmp/a.wav", language: nil) == "done"
        )
    }

    @Test("a program that cannot be started is an error")
    func cannotStart() async throws {
        await #expect(throws: LocalWhisperError.couldNotStart) {
            try await LocalWhisperCLI(path: tools.notAProgram).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
    }
}
