import Domain
import OSLog

/// The live log: events go to the unified log of the app. `log show --predicate 'subsystem ==
/// "dev.claudiojara.susurro"'` reads them. Failures are errors, and the rest are at the default level, which the system
/// keeps; the info level lives only in memory and `log show` would not find it afterwards. A line is built from fixed words and the names an event carries, which are
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
        case .processingCapReached: (.error, "processing did not finish within its total time limit")
        case .recordingCapReached: (.default, "recording reached its time limit")
        case .releaseWaitExpired: (.default, "the key was not released in time, pasting anyway")
        case .captureStopAbandoned: (.error, "capture did not stop in time and was abandoned")
        case .shutdownDrainAbandoned: (.error, "shutdown stopped waiting for the paste to finish")
        case .pasteNotCompleted(let cause): (.error, "paste not completed: \(cause)")
        case .pasteboardWriteRefused: (.error, "the pasteboard refused a write")
        case .clipboardRestoreFailed: (.error, "the pasteboard refused the old contents")
        case .clipboardNotRestored(let reason): (.default, "the old clipboard was not put back: \(reason)")
        case .styleResolved(let category, let tone, let source):
            (.default, "style: category=\(category) tone=\(tone) source=\(source)")
        case .clipboardRestoreAtTermination(let restored):
            (.default, restored ? "termination: the clipboard was put back" : "termination: no clipboard to put back")
        case .captureFirstBuffer(let frames, let sampleRate):
            (.default, "first tap buffer: \(frames) frames at \(Int(sampleRate)) Hz")
        case .appLaunched: (.default, "app launched")
        case .appTerminating: (.default, "app terminating")
        case .modelPrepareRequested: (.default, "speech model: prepare requested")
        case .modelReadiness(let state): (.default, "speech model: \(state)")
        case .settingNotStored(let key): (.error, "setting not stored, its value has no stored form: \(key)")
        case .settingUnreadable(let key): (.error, "setting unreadable, its default is used: \(key)")
        case .permissionStatusChanged(let permission, let from, let to):
            (.default, Self.describeChange(of: permission, from: from, to: to))
        case .permissionGuidanceShown(let permission):
            (.default, "permission \(permission): troubleshooting steps shown")
        case .permissionRequestEnded(let permission, let status):
            (.default, "permission \(permission): request ended, now \(status)")
        case .recordingVerified(let id, let milliseconds):
            (.default, "recording \(id).caf stored and verified: \(milliseconds) ms")
        case .recordingStoreFailed(let step): (.error, "recording store failed at \(step)")
        case .historyWriteFailed(let step): (.error, "history write failed at \(step)")
        case .voiceDetectionFailed: (.error, "voice detection failed, the recording goes to the recognizer whole")
        case .languageDriftDetected: (.default, "transcript in the wrong language, transcribing again")
        case .secretUnreadable(let account, let status):
            (.error, "key store unreadable for \(account.rawValue): status \(status)")
        case .cloudRequestFailed(let provider, let reason): (.error, "cloud request to \(provider) failed: \(reason)")
        case .microphoneFallback: (.default, "the chosen microphone is not connected, using the system default")
        case .microphoneSelectionFailed(let status):
            (.error, "the chosen microphone could not be selected: status \(status), using the system default")
        case .mediaPlayback(let paused):
            (.default, paused ? "media paused for a recording" : "media resumed after a recording")
        case .commandNoResult(let reason): (.info, "command replaced nothing: \(reason)")
        case .correctionWatchEnded(let reason):
            (.default, "correction watch ended: \(reason.rawValue)")
        }
    }

    /// A change from granted is a revocation, which the line says. The first read has no status before it.
    private static func describeChange(of permission: Permission, from: PermissionStatus?, to: PermissionStatus)
        -> String
    {
        let before = from.map { String(describing: $0) } ?? "unread"
        let revoked = from == .granted && to != .granted
        return "permission \(permission)\(revoked ? " revoked" : ""): \(before) -> \(to)"
    }
}
