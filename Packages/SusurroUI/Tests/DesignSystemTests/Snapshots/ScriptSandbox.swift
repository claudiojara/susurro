import Foundation

/// A scratch folder to run one of the scripts in `.github/scripts` in. `gh` is a stand-in that writes each call to a log
/// and answers from environment variables, so the scripts run here exactly as they run in a workflow, except that they
/// reach no GitHub.
struct ScriptSandbox {
    struct Result {
        let status: Int32
        /// Standard output and standard error together.
        let output: String
    }

    let folder: ScratchFolder

    var callLog: URL { folder.file("gh-calls.log") }
    var githubOutput: URL { folder.file("github-output") }

    /// The calls the script made to `gh`, one per entry.
    var ghCalls: [String] {
        ((try? String(contentsOf: callLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    var writtenOutputs: [String] {
        ((try? String(contentsOf: githubOutput, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    init() throws {
        folder = try ScratchFolder()
        try folder.write("bin/gh", Self.standIn)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.file("bin/gh").path)
        try folder.write("gh-calls.log", "")
        try folder.write("github-output", "")
    }

    private static let standIn = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$STUB_LOG"
        case "$1 $2" in
          "api --method") printf '%s' "${STUB_PULLS:-[]}" ;;
          "run list") printf '%s' "${STUB_RUNS:-[]}" ;;
          "workflow run") ;;
          *) echo "unexpected gh call: $*" >&2; exit 64 ;;
        esac
        """

    /// Runs `.github/scripts/<script>` with bash, in `directory` (the sandbox itself when not given).
    func run(
        _ script: String, arguments: [String] = [], environment: [String: String] = [:], in directory: URL? = nil
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [PackageLayout.repositoryFile(".github/scripts/\(script)").path] + arguments
        process.currentDirectoryURL = directory ?? folder.url
        var variables = [
            "PATH": "\(folder.file("bin").path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
            "HOME": folder.url.path,
            "STUB_LOG": callLog.path,
            "GITHUB_OUTPUT": githubOutput.path,
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
        ]
        variables.merge(environment) { _, new in new }
        process.environment = variables
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a program (git, tar) in `directory` and returns what it printed. A failure stops the test.
    @discardableResult
    func tool(_ launch: String, _ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = [
            "PATH": "/usr/bin:/bin:/opt/homebrew/bin", "HOME": folder.url.path,
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ToolFailure(command: ([launch] + arguments).joined(separator: " "), output: text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func git(_ arguments: [String], in directory: URL) throws -> String {
        try tool("/usr/bin/git", arguments, in: directory)
    }

    struct ToolFailure: Error, CustomStringConvertible {
        let command: String
        let output: String
        var description: String { "\(command) failed: \(output)" }
    }
}
