import Domain
import Testing

@testable import Presentation

@Suite("Menu content")
struct MenuContentTests {
    @Test("the hotkey hint names the key to hold")
    func hotkeyHint() {
        let content = MenuContent.make(
            microphone: .granted, accessibility: .granted, restriction: nil, readiness: .ready)

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
        let row = MenuContent.make(microphone: status, accessibility: .granted, restriction: nil, readiness: .ready)
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
        let row = MenuContent.make(microphone: .granted, accessibility: status, restriction: nil, readiness: .ready)
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
            microphone: .granted, accessibility: .granted, restriction: nil, readiness: readiness)

        #expect(content.modelLine == line)
    }

    @Test("a long reason is cut short so that the menu stays readable")
    func longReasonIsCut() {
        let reason = String(repeating: "x", count: 300)
        let line = MenuContent.make(
            microphone: .granted, accessibility: .granted, restriction: nil,
            readiness: .unavailable(reason, retryable: true)
        ).modelLine

        #expect(
            line
                == "Speech model: could not load (\(String(repeating: "x", count: 80))…). "
                + "Susurro will retry loading the model shortly.")
    }

    @Test(
        "the menu says what the missing required permissions cost, with the words the onboarding shows",
        arguments: [
            (
                [Permission.microphone, .accessibility],
                "Dictation is off until Microphone is allowed. "
                    + "Dictated text goes to the clipboard until Accessibility is allowed."
            ),
            ([.microphone], "Dictation is off until Microphone is allowed."),
            ([.accessibility], "Dictated text goes to the clipboard until Accessibility is allowed."),
        ]
    )
    func restrictionMessage(missing: [Permission], expected: String) throws {
        let restriction = try #require(DictationRestriction(missing: missing))

        let content = MenuContent.make(
            microphone: .denied, accessibility: .denied, restriction: restriction, readiness: .ready)

        #expect(content.restrictionMessage == expected)
    }

    @Test("with nothing missing the menu says nothing about dictation")
    func noRestrictionMessage() {
        let content = MenuContent.make(
            microphone: .granted, accessibility: .granted, restriction: nil, readiness: .ready)

        #expect(content.restrictionMessage == nil)
    }

    @Test(
        "while a required permission is missing the menu offers to set Susurro up, and otherwise it does not",
        arguments: [Permission.microphone, .accessibility]
    )
    func setUpItem(missing: Permission) throws {
        let restriction = try #require(DictationRestriction(missing: [missing]))

        let off = MenuContent.make(
            microphone: .granted, accessibility: .denied, restriction: restriction, readiness: .ready)
        let on = MenuContent.make(
            microphone: .granted, accessibility: .granted, restriction: nil, readiness: .ready)

        #expect(off.setUpTitle == "Set up Susurro…")
        #expect(on.setUpTitle == nil)
    }
}
