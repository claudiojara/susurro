import Domain
import Foundation

/// Why Local Whisper could not transcribe. The text is a fixed sentence: it never holds what the program printed, which
/// can be what the user said, or a path, which can be anything.
enum LocalWhisperError: Error, Sendable, Equatable {
    /// The configured program cannot be run: it is not an absolute path, is not there, or is not executable.
    case invalidExecutable(ExecutablePath.Problem)
    /// The configured address is not one on this Mac.
    case invalidEndpoint
    case couldNotStart
    case timedOut
    /// The program exited with a status other than zero.
    case failed(status: Int32)
    case emptyOutput
    case outputTooLarge
    case http(Int)
    case network
    case response

    var message: String {
        switch self {
        case .invalidExecutable: "the command cannot be run"
        case .invalidEndpoint: "the address must be on this Mac"
        case .couldNotStart: "the command did not start"
        case .timedOut: "timeout"
        case .failed(let status): "exit \(status)"
        case .emptyOutput: "empty output"
        case .outputTooLarge: "output too large"
        case .http(let status): "http-\(status)"
        case .network: "network"
        case .response: "response"
        }
    }

    /// The error the pipeline sees. The audio is kept for a retry, as for any failure of a recognizer.
    var recognitionError: RecognitionError { .engineFailed("Local Whisper: \(message)") }
}

/// Runs the user's own command line speech tool on a WAV file and reads the transcript from what it prints.
///
/// The tool is called as `<path> <wav file>`: the file is its only argument, and the language, when one is pinned, is in
/// the environment variable `SUSURRO_LANGUAGE`. A script of the user's can turn that into whatever its tool takes. There
/// is no shell: the path is an absolute path that was checked, the arguments are an array, and nothing in a name of a
/// file can be read as a command. The tool has `timeout` to finish (on the injected clock), is killed when the task is
/// cancelled, and its output is read as it comes, up to a limit.
struct LocalWhisperCLI: Sendable {
    /// The most the tool may print, in bytes. A transcript is far smaller.
    static let outputLimit = 1_048_576
    static let languageVariable = "SUSURRO_LANGUAGE"

    private let executable: URL
    private let timeout: Duration
    private let clock: any Clock<Duration>
    private let baseEnvironment: [String: String]

    /// - Parameter path: The program. A path that is relative, missing, or not executable is refused.
    init(
        path: String, timeout: Duration = .seconds(60), clock: any Clock<Duration> = ContinuousClock(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        if let problem = ExecutablePath.validate(path) { throw LocalWhisperError.invalidExecutable(problem) }
        executable = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
        self.timeout = timeout
        self.clock = clock
        baseEnvironment = environment
    }

    /// The arguments of the program: the path of the file, as one element, whatever characters it has.
    static func arguments(wavPath: String) -> [String] { [wavPath] }

    /// What the tool prints for the file, trimmed. Throws `CancellationError` when the task is cancelled, and the
    /// program is killed.
    func transcribe(wavPath: String, language: String?) async throws -> String {
        var environment = baseEnvironment
        environment[Self.languageVariable] = language
        let run = ManagedProcess(
            executable: executable, arguments: Self.arguments(wavPath: wavPath), environment: environment,
            outputLimit: Self.outputLimit)
        do {
            try run.start()
        } catch {
            throw LocalWhisperError.couldNotStart
        }
        let clock = clock
        let timeout = timeout
        let outcome = await withTaskCancellationHandler {
            await withTaskGroup(of: ProcessOutcome?.self) { group in
                group.addTask { await run.wait() }
                group.addTask {
                    guard (try? await clock.sleep(for: timeout)) != nil else { return nil }
                    run.kill()
                    return nil
                }
                var result = ProcessOutcome.killed
                for await finished in group {
                    if let finished {
                        result = finished
                        group.cancelAll()
                        break
                    }
                }
                return result
            }
        } onCancel: {
            run.kill()
        }
        try Task.checkCancellation()
        switch outcome {
        case .exited(let status, let output):
            guard status == 0 else { throw LocalWhisperError.failed(status: status) }
            let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw LocalWhisperError.emptyOutput }
            return text
        case .outputTooLarge: throw LocalWhisperError.outputTooLarge
        case .killed: throw LocalWhisperError.timedOut
        }
    }
}
