import Domain
import Testing

@testable import Presentation

@Suite("Menu content")
struct MenuContentTests {
    @Test("the hotkey hint names the key to hold")
    func hotkeyHint() {
        let content = MenuContent.make(
            microphone: .granted, accessibility: .granted, disabledReason: nil, readiness: .ready)

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
        let row = MenuContent.make(microphone: status, accessibility: .granted, disabledReason: nil, readiness: .ready)
            .microphone

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
        let row = MenuContent.make(microphone: .granted, accessibility: status, disabledReason: nil, readiness: .ready)
            .accessibility

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
            (.loading(progress: .nan), "Speech model: preparing…"),
            (.loading(progress: .infinity), "Speech model: preparing…"),
            (.loading(progress: 1.7), "Speech model: preparing… 100%"),
            (.notInstalled, "Speech model: not installed. Restart Susurro to download it."),
            (
                .unavailable("no network", retryable: true),
                "Speech model: could not load (no network). Susurro will retry loading the model shortly."
            ),
            (
                .unavailable("the model is damaged", retryable: false),
                "Speech model: could not load (the model is damaged). Restart Susurro."
            ),
        ]
    )
    func modelLine(readiness: RecognizerReadiness, line: String) {
        let content = MenuContent.make(
            microphone: .granted, accessibility: .granted, disabledReason: nil, readiness: readiness)

        #expect(content.modelLine == line)
    }

    @Test("a long reason is cut short so that the menu stays readable")
    func longReasonIsCut() {
        let reason = String(repeating: "x", count: 300)
        let line = MenuContent.make(
            microphone: .granted, accessibility: .granted, disabledReason: nil,
            readiness: .unavailable(reason, retryable: true)
        ).modelLine

        #expect(
            line
                == "Speech model: could not load (\(String(repeating: "x", count: 80))…). "
                + "Susurro will retry loading the model shortly.")
    }

    @Test("the menu says why dictation is off, with the reason the onboarding shows")
    func disabledMessage() throws {
        let reason = try #require(DictationDisabledReason(blocking: [.microphone, .accessibility]))

        let off = MenuContent.make(
            microphone: .denied, accessibility: .denied, disabledReason: reason, readiness: .ready)
        let single = MenuContent.make(
            microphone: .granted, accessibility: .denied,
            disabledReason: DictationDisabledReason(blocking: [.accessibility]), readiness: .ready)

        #expect(off.disabledMessage == "Dictation is off until Microphone and Accessibility are allowed.")
        #expect(single.disabledMessage == "Dictation is off until Accessibility is allowed.")
    }

    @Test("with nothing holding dictation back the menu says nothing about it")
    func noDisabledMessage() {
        let content = MenuContent.make(
            microphone: .granted, accessibility: .granted, disabledReason: nil, readiness: .ready)

        #expect(content.disabledMessage == nil)
    }
}
