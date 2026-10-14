import Foundation
import Synchronization

/// How a run of a process ended.
enum ProcessOutcome: Sendable, Equatable {
    /// The process exited, with this status and this much of its standard output.
    case exited(status: Int32, output: Data)
    /// The process wrote more than the limit, and was killed.
    case outputTooLarge
    /// Someone killed the process: the timeout, or a cancelled task.
    case killed
}

/// One run of a program, with no shell: the executable is given by its path and the arguments as an array, so nothing in
/// an argument is ever read as a command. The standard output is read as it comes and bounded, the standard error is
/// thrown away, and the program has no input.
///
/// The process can be killed from any thread, and a kill ends the run at once without waiting for the pipe: a program
/// that started children keeps the pipe open after it is gone.
///
/// `Process` is not `Sendable`. It is only started once, before anything else can reach it, and afterwards only killed,
/// and everything that changes is behind the mutex.
final class ManagedProcess: @unchecked Sendable {
    private struct State {
        var output = Data()
        var sawEndOfOutput = false
        var exitStatus: Int32?
        var outcome: ProcessOutcome?
        var waiter: CheckedContinuation<ProcessOutcome, Never>?
        var started = false
    }

    private let process = Process()
    private let pipe = Pipe()
    private let state = Mutex(State())
    private let outputLimit: Int

    init(executable: URL, arguments: [String], environment: [String: String], outputLimit: Int) {
        self.outputLimit = outputLimit
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
    }

    /// Starts the program. Throws when it cannot be started.
    func start() throws {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.received(chunk)
        }
        process.terminationHandler = { [weak self] process in
            self?.exited(status: process.terminationStatus)
        }
        do {
            try process.run()
            state.withLock { $0.started = true }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    /// Waits for the end of the run.
    func wait() async -> ProcessOutcome {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if let outcome = state.outcome {
                    continuation.resume(returning: outcome)
                } else {
                    state.waiter = continuation
                }
            }
        }
    }

    /// Kills the program, and ends the run as `killed` unless it has ended already.
    func kill() {
        killProcess()
        finish(.killed)
    }

    // MARK: Events

    private func received(_ chunk: Data) {
        if chunk.isEmpty {
            pipe.fileHandleForReading.readabilityHandler = nil
            state.withLock { $0.sawEndOfOutput = true }
            completeIfDone()
            return
        }
        let tooLarge = state.withLock { state -> Bool in
            if state.output.count + chunk.count > outputLimit { return true }
            state.output.append(chunk)
            return false
        }
        if tooLarge {
            killProcess()
            finish(.outputTooLarge)
        }
    }

    private func killProcess() {
        guard state.withLock({ $0.started }), process.isRunning else { return }
        Foundation.kill(process.processIdentifier, SIGKILL)
    }

    private func exited(status: Int32) {
        state.withLock { $0.exitStatus = status }
        completeIfDone()
    }

    /// The run is over when the program has exited and its output has ended.
    private func completeIfDone() {
        let outcome = state.withLock { state -> ProcessOutcome? in
            guard let status = state.exitStatus, state.sawEndOfOutput else { return nil }
            return .exited(status: status, output: state.output)
        }
        if let outcome { finish(outcome) }
    }

    private func finish(_ outcome: ProcessOutcome) {
        let waiter = state.withLock { state -> CheckedContinuation<ProcessOutcome, Never>? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            defer { state.waiter = nil }
            return state.waiter
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        waiter?.resume(returning: outcome)
    }
}
