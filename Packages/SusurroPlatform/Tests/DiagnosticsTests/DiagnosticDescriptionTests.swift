import Domain
import OSLog
import Testing

@testable import Diagnostics

@Suite("Diagnostic descriptions")
struct DiagnosticDescriptionTests {
    @Test(
        "each event has a level and a line that names it",
        arguments: [
            (
                DiagnosticEvent.dictationFailed(kind: "timedOut.readiness"), OSLogType.error,
                "dictation failed: timedOut.readiness"
            ),
            (.captureStreamFailed(errorType: "CaptureError"), .error, "capture stream failed: CaptureError"),
            (.captureStopAbandoned, .error, "capture did not stop in time and was abandoned"),
            (.shutdownDrainAbandoned, .error, "shutdown stopped waiting for the paste to finish"),
            (.pasteNotCompleted(cause: "noRead"), .error, "paste not completed: noRead"),
            (.pasteboardWriteRefused, .error, "the pasteboard refused a write"),
            (.clipboardRestoreFailed, .error, "the pasteboard refused the old contents"),
            (
                .captureFirstBuffer(frames: 1_024, sampleRate: 48_000), .info,
                "first tap buffer: 1024 frames at 48000 Hz"
            ),
            (.appLaunched, .info, "app launched"),
            (.modelPrepareRequested, .info, "speech model: prepare requested"),
            (.modelReadiness("loading"), .info, "speech model: loading"),
            (.modelReadiness("ready"), .info, "speech model: ready"),
            (
                .launchPermissions(microphone: "granted", accessibility: "denied"), .info,
                "permissions at launch: microphone granted, accessibility denied"
            ),
        ])
    func descriptions(event: DiagnosticEvent, level: OSLogType, line: String) {
        let description = OSLogDiagnostics.describe(event)

        #expect(description.level == level)
        #expect(description.line == line)
    }
}
