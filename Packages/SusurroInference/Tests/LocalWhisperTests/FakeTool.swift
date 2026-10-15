import Foundation

/// The fake command line tools of the tests: small scripts, all written once, before the first test starts a process.
///
/// A script that is written while another test starts a process can be refused when it is run, because the new process
/// may have inherited the file that was being written ("text file busy"). The tools are therefore made in one place that
/// every test goes through first, and no test writes an executable afterwards. What differs between tests goes in the
/// environment of the run, not in the script.
struct FakeTools: Sendable {
    static let shared = FakeTools()

    /// Prints the arguments it got, one for each line, and the pinned language.
    let echo: String
    /// Prints a transcript with blanks around it.
    let say: String
    /// Writes its process id to the file named by `PIDFILE`, and then waits for a long time.
    let slow: String
    /// Prints words and exits with status 3.
    let failWithThree: String
    /// Exits with status 1 and prints nothing.
    let failWithOne: String
    let silent: String
    let blanks: String
    /// Prints far more than the limit.
    let flood: String
    /// Reads its input to the end, and prints a word.
    let readsInput: String
    /// Prints how many bytes the file it was given has.
    let sizeOfFile: String
    let hello: String
    /// A file that is not executable.
    let notExecutable: String
    /// A file that is executable but is not a program.
    let notAProgram: String

    private init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-fake-tools")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func make(_ name: String, _ body: String, mode: Int = 0o755, binary: Data? = nil) -> String {
            let file = directory.appendingPathComponent(name)
            try? (binary ?? Data("#!/bin/sh\n\(body)\n".utf8)).write(to: file)
            try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
            return file.path
        }
        echo = make(
            "echo.sh",
            """
            printf 'argc=%s\\n' "$#"
            for a in "$@"; do printf 'arg=%s\\n' "$a"; done
            printf 'language=%s\\n' "$SUSURRO_LANGUAGE"
            """)
        say = make("say.sh", "printf '  hola equipo\\n\\n'")
        slow = make("slow.sh", "echo $$ > \"$PIDFILE\"\nexec sleep 1000")
        failWithThree = make("fail3.sh", "echo 'secret words the user said'\necho 'oops' >&2\nexit 3")
        failWithOne = make("fail1.sh", "exit 1")
        silent = make("silent.sh", "exit 0")
        blanks = make("blanks.sh", "printf '  \\n\\n'")
        flood = make("flood.sh", "yes 'blah blah blah' | head -c 4000000")
        readsInput = make("reads.sh", "cat > /dev/null\necho done")
        sizeOfFile = make("size.sh", "printf 'bytes=%s' \"$(wc -c < \"$1\" | tr -d ' ')\"")
        hello = make("hello.sh", "echo hi")
        notExecutable = make("plain.sh", "echo hi", mode: 0o644)
        notAProgram = make("broken", "", binary: Data([0, 1, 2, 3]))
    }
}

/// A folder for one test: where a tool writes the files a test looks at, and the temporary folder of a recognizer.
final class ToolFolder: @unchecked Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-run-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Removes the folder. A test calls it in a `defer`: a value that is only used to name files can be released before
    /// the test has run its tools, so the folder is not removed by the release.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> String { url.appendingPathComponent(name).path }

    var contents: [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] }
}

/// The environment of a run of a tool: the one of the test process and `extra`.
func environment(_ extra: [String: String] = [:]) -> [String: String] {
    ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
}

/// Whether a process is still alive.
func isAlive(pid: Int32) -> Bool {
    kill(pid, 0) == 0
}

/// Waits up to ten seconds for a condition that another thread makes true (a loaded CI runner can be slow).
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
