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
            (.processingCapReached, .error, "processing did not finish within its total time limit"),
            (.recordingCapReached, .default, "recording reached its time limit"),
            (.releaseWaitExpired, .default, "the key was not released in time, pasting anyway"),
            (.captureStopAbandoned, .error, "capture did not stop in time and was abandoned"),
            (.shutdownDrainAbandoned, .error, "shutdown stopped waiting for the paste to finish"),
            (.pasteNotCompleted(cause: "noRead"), .error, "paste not completed: noRead"),
            (.pasteboardWriteRefused, .error, "the pasteboard refused a write"),
            (.clipboardRestoreFailed, .error, "the pasteboard refused the old contents"),
            (.clipboardNotRestored(reason: "tooLarge"), .default, "the old clipboard was not put back: tooLarge"),
            (
                .styleResolved(category: "work_chat", tone: "casual", source: "bundle"), .default,
                "style: category=work_chat tone=casual source=bundle"
            ),
            (
                .captureFirstBuffer(frames: 1_024, sampleRate: 48_000), .default,
                "first tap buffer: 1024 frames at 48000 Hz"
            ),
            (.clipboardRestoreAtTermination(restored: true), .default, "termination: the clipboard was put back"),
            (.clipboardRestoreAtTermination(restored: false), .default, "termination: no clipboard to put back"),
            (.appLaunched, .default, "app launched"),
            (.appTerminating, .default, "app terminating"),
            (.modelPrepareRequested, .default, "speech model: prepare requested"),
            (.modelReadiness("loading"), .default, "speech model: loading"),
            (.modelReadiness("ready"), .default, "speech model: ready"),
            (
                .settingNotStored(key: "hotkey.combo"), .error,
                "setting not stored, its value has no stored form: hotkey.combo"
            ),
            (
                .settingUnreadable(key: "overlay.edge"), .error,
                "setting unreadable, its default is used: overlay.edge"
            ),
            (
                .permissionStatusChanged(permission: .microphone, from: nil, to: .granted), .default,
                "permission microphone: unread -> granted"
            ),
            (
                .permissionStatusChanged(permission: .inputMonitoring, from: .notDetermined, to: .denied), .default,
                "permission inputMonitoring: notDetermined -> denied"
            ),
            (
                .permissionStatusChanged(permission: .accessibility, from: .granted, to: .denied), .default,
                "permission accessibility revoked: granted -> denied"
            ),
            (
                .permissionGuidanceShown(permission: .screenRecording), .default,
                "permission screenRecording: troubleshooting steps shown"
            ),
            (
                .permissionRequestEnded(permission: .accessibility, status: .denied), .default,
                "permission accessibility: request ended, now denied"
            ),
        ])
    func descriptions(event: DiagnosticEvent, level: OSLogType, line: String) {
        let description = OSLogDiagnostics.describe(event)

        #expect(description.level == level)
        #expect(description.line == line)
    }
}
