import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import LocalWhisper

/// The threat matrix of the subprocess: what an argument can do, which paths are run, and how a run ends.
@Suite("Local Whisper command line tool", .timeLimit(.minutes(1)))
struct LocalWhisperCLITests {
    private let echo = """
        printf 'argc=%s\\n' "$#"
        for a in "$@"; do printf 'arg=%s\\n' "$a"; done
        printf 'language=%s\\n' "$SUSURRO_LANGUAGE"
        """

    // MARK: Arguments

    @Test("the path of the file is passed as one argument, whatever characters it has, and no shell reads it")
    func hostilePaths() async throws {
        let folder = ToolFolder()
        let tool = folder.script("echo.sh", echo)
        let trap = folder.path("pwned")
        let paths = [
            "/tmp/with space/a b.wav", "/tmp/x; touch \(trap).wav", "/tmp/$(touch \(trap)).wav",
            "/tmp/`touch \(trap)`.wav", "/tmp/it's \"quoted\".wav", "/tmp/a | b && c > d.wav", "/tmp/-rf.wav",
            "/tmp/new\nline.wav",
        ]

        for path in paths {
            let output = try await LocalWhisperCLI(path: tool).transcribe(wavPath: path, language: nil)

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
        let folder = ToolFolder()
        let tool = folder.script("echo.sh", echo)

        let pinned = try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: "es")
        let automatic = try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil)

        #expect(pinned.hasSuffix("language=es"))
        #expect(automatic.hasSuffix("language="))
    }

    @Test("what the tool prints is the transcript, trimmed")
    func transcript() async throws {
        let folder = ToolFolder()
        let tool = folder.script("say.sh", "printf '  hola equipo\\n\\n'")

        #expect(try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil) == "hola equipo")
    }

    // MARK: Which paths are run

    @Test("a relative, missing, or not executable path is refused as an invalid executable")
    func invalidExecutable() throws {
        let folder = ToolFolder()
        let notExecutable = folder.script("plain.sh", "echo hi", executable: false)
        let cases: [(String, ExecutablePath.Problem)] = [
            ("whisper", .notAbsolute), ("./whisper", .notAbsolute), ("../bin/whisper", .notAbsolute),
            ("/definitely/not/here", .missing), (folder.url.path, .missing), (notExecutable, .notExecutable),
            ("", .empty),
        ]

        for (path, problem) in cases {
            #expect(throws: LocalWhisperError.invalidExecutable(problem), "the path \(path)") {
                try LocalWhisperCLI(path: path)
            }
        }
    }

    // MARK: How a run ends

    @Test("a tool that runs past the limit is killed, and the run fails as a timeout")
    func timeout() async throws {
        let folder = ToolFolder()
        let pidFile = folder.path("pid")
        let tool = folder.script("slow.sh", "echo $$ > '\(pidFile)'\nexec sleep 1000")
        let clock = ManualClock()
        let cli = try LocalWhisperCLI(path: tool, timeout: .seconds(60), clock: clock)
        let before = clock.suspendedSleeps

        let run = Task { try await cli.transcribe(wavPath: "/tmp/a.wav", language: nil) }
        await clock.waitForSleeps(before + 1)
        #expect(await eventually { FileManager.default.fileExists(atPath: pidFile) })
        let pid = try #require(
            Int32(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
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
        let pidFile = folder.path("pid")
        let tool = folder.script("slow.sh", "echo $$ > '\(pidFile)'\nexec sleep 1000")
        let clock = ManualClock()
        let cli = try LocalWhisperCLI(path: tool, clock: clock)
        let before = clock.suspendedSleeps

        let run = Task { try await cli.transcribe(wavPath: "/tmp/a.wav", language: nil) }
        await clock.waitForSleeps(before + 1)
        #expect(await eventually { FileManager.default.fileExists(atPath: pidFile) })
        let pid = try #require(
            Int32(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))

        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await eventually { !isAlive(pid: pid) }, "the tool is still running after the cancel")
    }

    @Test("a tool that exits with an error status is an error that names the status and not the output")
    func nonZeroExit() async throws {
        let folder = ToolFolder()
        let tool = folder.script("fail.sh", "echo 'secret words the user said'\necho 'oops' >&2\nexit 3")

        await #expect(throws: LocalWhisperError.failed(status: 3)) {
            try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
        #expect(LocalWhisperError.failed(status: 3).recognitionError == .engineFailed("Local Whisper: exit 3"))
    }

    @Test("a tool that prints nothing, or only blanks, is an error")
    func emptyOutput() async throws {
        let folder = ToolFolder()
        let nothing = folder.script("nothing.sh", "exit 0")
        let blanks = folder.script("blanks.sh", "printf '  \\n\\n'")

        for tool in [nothing, blanks] {
            await #expect(throws: LocalWhisperError.emptyOutput) {
                try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil)
            }
        }
    }

    @Test("a tool that prints more than the limit is killed and the run fails")
    func tooMuchOutput() async throws {
        let folder = ToolFolder()
        let tool = folder.script("flood.sh", "yes 'blah blah blah' | head -c 4000000")

        await #expect(throws: LocalWhisperError.outputTooLarge) {
            try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
    }

    @Test("the tool has no input, so one that reads it does not wait")
    func noInput() async throws {
        let folder = ToolFolder()
        let tool = folder.script("reads.sh", "cat > /dev/null\necho done")

        #expect(try await LocalWhisperCLI(path: tool).transcribe(wavPath: "/tmp/a.wav", language: nil) == "done")
    }

    @Test("a program that cannot be started is an error")
    func cannotStart() async throws {
        let folder = ToolFolder()
        // Executable, but not a program the system can run: no interpreter line and not a binary.
        let file = folder.path("broken")
        try Data([0, 1, 2, 3]).write(to: URL(fileURLWithPath: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file)

        await #expect(throws: LocalWhisperError.couldNotStart) {
            try await LocalWhisperCLI(path: file).transcribe(wavPath: "/tmp/a.wav", language: nil)
        }
    }
}
