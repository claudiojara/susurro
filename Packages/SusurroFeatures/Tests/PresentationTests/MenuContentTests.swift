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
        "the microphone row says whether it is allowed, and offers the step that fits unless it is",
        arguments: [
            (PermissionStatus.granted, "Microphone: allowed", true, nil as PermissionStep.Action?, nil as String?),
            (.denied, "Microphone: not allowed", false, .openSettings, "Open System Settings for Microphone…"),
            (.notDetermined, "Microphone: not decided yet", false, .request, "Allow Microphone…"),
        ]
    )
    func microphoneRow(
        status: PermissionStatus, title: String, isGranted: Bool, kind: PermissionStep.Action?, actionTitle: String?
    ) {
        let row = MenuContent.make(microphone: status, accessibility: .granted, restriction: nil, readiness: .ready)
            .microphone

        #expect(row.permission == .microphone)
        #expect(row.title == title)
        #expect(row.isGranted == isGranted)
        #expect(row.action?.kind == kind)
        #expect(row.action?.title == actionTitle)
    }

    @Test(
        "the Accessibility row says whether it is allowed, and asks first because denied may mean never asked",
        arguments: [
            (PermissionStatus.granted, "Accessibility: allowed", true, nil as PermissionStep.Action?, nil as String?),
            (.denied, "Accessibility: not allowed", false, .request, "Allow Accessibility…"),
            (.notDetermined, "Accessibility: not decided yet", false, .request, "Allow Accessibility…"),
        ]
    )
    func accessibilityRow(
        status: PermissionStatus, title: String, isGranted: Bool, kind: PermissionStep.Action?, actionTitle: String?
    ) {
        let row = MenuContent.make(microphone: .granted, accessibility: status, restriction: nil, readiness: .ready)
            .accessibility

        #expect(row.permission == .accessibility)
        #expect(row.title == title)
        #expect(row.isGranted == isGranted)
        #expect(row.action?.kind == kind)
        #expect(row.action?.title == actionTitle)
    }

    @Test("a permission nobody has decided on offers to allow it, not to open System Settings")
    func notDecidedOffersAllow() {
        let content = MenuContent.make(
            microphone: .notDetermined, accessibility: .notDetermined, restriction: nil, readiness: .ready)

        #expect(
            content.microphone.action == MenuContent.PermissionRow.Action(kind: .request, title: "Allow Microphone…"))
        #expect(
            content.accessibility.action
                == MenuContent.PermissionRow.Action(kind: .request, title: "Allow Accessibility…"))
    }

    @Test("a refusal offers System Settings for Microphone, and a request first for Accessibility")
    func deniedOffersSettings() {
        let content = MenuContent.make(
            microphone: .denied, accessibility: .denied, restriction: nil, readiness: .ready)
        let afterTheRequest = MenuContent.make(
            microphone: .denied, accessibility: .denied, followUps: [.accessibility: .sentToSettings],
            restriction: nil, readiness: .ready)

        #expect(
            content.microphone.action
                == MenuContent.PermissionRow.Action(
                    kind: .openSettings, title: "Open System Settings for Microphone…"))
        #expect(
            content.accessibility.action
                == MenuContent.PermissionRow.Action(kind: .request, title: "Allow Accessibility…"))
        #expect(
            afterTheRequest.accessibility.action
                == MenuContent.PermissionRow.Action(
                    kind: .openSettings, title: "Open System Settings for Accessibility…"))
    }

    @Test(
        "a follow-up changes the step as it does in the onboarding: nothing while the prompt is up, Settings after",
        arguments: [
            (nil as PermissionsMonitor.FollowUp?, PermissionStep.Action.request),
            (.requesting, nil),
            (.sentToSettings, .openSettings),
            (.stale, .openSettings),
        ]
    )
    func followUpChangesTheStep(followUp: PermissionsMonitor.FollowUp?, expected: PermissionStep.Action?) {
        let content = MenuContent.make(
            microphone: .notDetermined, accessibility: .granted,
            followUps: followUp.map { [.microphone: $0] } ?? [:], restriction: nil, readiness: .ready)

        #expect(content.microphone.action?.kind == expected)
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
