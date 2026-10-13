import Domain
import Testing

@testable import Presentation

@Suite("Menu content")
struct MenuContentTests {
    @Test("the hotkey hint names the key to hold")
    func hotkeyHint() {
        let content = MenuContent.make(microphone: .granted, accessibility: .granted, readiness: .ready)

        #expect(content.hotkeyHint == "Hold Control-Option-D to dictate")
    }

    @Test(
        "the microphone row says whether it is allowed, and offers System Settings unless it is",
        arguments: [
            (PermissionStatus.granted, "Microphone: allowed", true, nil as String?),
            (.denied, "Microphone: not allowed", false, "Open System Settings for Microphone…"),
            (.notDetermined, "Microphone: not decided yet", false, "Open System Settings for Microphone…"),
        ]
    )
    func microphoneRow(status: PermissionStatus, title: String, isGranted: Bool, action: String?) {
        let row = MenuContent.make(microphone: status, accessibility: .granted, readiness: .ready).microphone

        #expect(row.permission == .microphone)
        #expect(row.title == title)
        #expect(row.isGranted == isGranted)
        #expect(row.settingsActionTitle == action)
    }

    @Test(
        "the Accessibility row says whether it is allowed, and offers System Settings unless it is",
        arguments: [
            (PermissionStatus.granted, "Accessibility: allowed", true, nil as String?),
            (.denied, "Accessibility: not allowed", false, "Open System Settings for Accessibility…"),
            (.notDetermined, "Accessibility: not decided yet", false, "Open System Settings for Accessibility…"),
        ]
    )
    func accessibilityRow(status: PermissionStatus, title: String, isGranted: Bool, action: String?) {
        let row = MenuContent.make(microphone: .granted, accessibility: status, readiness: .ready).accessibility

        #expect(row.permission == .accessibility)
        #expect(row.title == title)
        #expect(row.isGranted == isGranted)
        #expect(row.settingsActionTitle == action)
    }

    @Test(
        "the model line says what the speech model is doing",
        arguments: [
            (RecognizerReadiness.ready, "Speech model: ready"),
            (.loading(progress: 0), "Speech model: preparing…"),
            (.loading(progress: 0.42), "Speech model: preparing… 42%"),
            (.notInstalled, "Speech model: not installed. Open the Susurro settings to install it."),
            (
                .unavailable("no network", retryable: true),
                "Speech model: could not load (no network). Hold the key to try again."
            ),
            (
                .unavailable("the model is damaged", retryable: false),
                "Speech model: could not load (the model is damaged). Restart Susurro."
            ),
        ]
    )
    func modelLine(readiness: RecognizerReadiness, line: String) {
        let content = MenuContent.make(microphone: .granted, accessibility: .granted, readiness: readiness)

        #expect(content.modelLine == line)
    }

    @Test("a long reason is cut short so that the menu stays readable")
    func longReasonIsCut() {
        let reason = String(repeating: "x", count: 300)
        let line = MenuContent.make(
            microphone: .granted, accessibility: .granted, readiness: .unavailable(reason, retryable: true)
        ).modelLine

        #expect(line == "Speech model: could not load (\(String(repeating: "x", count: 80))…). Hold the key to try again.")
    }
}
