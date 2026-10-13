import Domain
import OSLog

/// The live log: events go to the unified log of the app. `log show --predicate 'subsystem ==
/// "dev.claudiojara.susurro"'` reads them. A line is built from fixed words and the names an event carries, which are
/// not private (kinds, causes, sizes), so it is logged as public: the system would otherwise redact it, and there is no
/// text of the user in it.
public struct OSLogDiagnostics: DiagnosticsLog {
    private let logger: Logger

    public init(subsystem: String = "dev.claudiojara.susurro", category: String = "pipeline") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(_ event: DiagnosticEvent) {
        let (level, line) = Self.describe(event)
        logger.log(level: level, "\(line, privacy: .public)")
    }

    /// The level and the line of an event.
    static func describe(_ event: DiagnosticEvent) -> (level: OSLogType, line: String) {
        switch event {
        case .dictationFailed(let kind): (.error, "dictation failed: \(kind)")
        case .captureStreamFailed(let errorType): (.error, "capture stream failed: \(errorType)")
        case .captureStopAbandoned: (.error, "capture did not stop in time and was abandoned")
        case .shutdownDrainAbandoned: (.error, "shutdown stopped waiting for the paste to finish")
        case .pasteNotCompleted(let cause): (.error, "paste not completed: \(cause)")
        case .pasteboardWriteRefused: (.error, "the pasteboard refused a write")
        case .clipboardRestoreFailed: (.error, "the pasteboard refused the old contents")
        case .captureFirstBuffer(let frames, let sampleRate):
            (.info, "first tap buffer: \(frames) frames at \(Int(sampleRate)) Hz")
        }
    }
}
