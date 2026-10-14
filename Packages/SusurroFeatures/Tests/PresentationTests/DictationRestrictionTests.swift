import Domain
import Testing

@testable import Presentation

private let microphoneSentence = "Dictation is off until Microphone is allowed."
private let accessibilitySentence = "Dictated text goes to the clipboard until Accessibility is allowed."

@MainActor
@Suite("Dictation restriction", .timeLimit(.minutes(1)))
struct DictationRestrictionTests {
    @Test("nothing missing means no restriction")
    func noRestrictionWhenNothingIsMissing() {
        #expect(DictationRestriction(missing: []) == nil)
    }

    @Test("a conditional permission restricts nothing, alone or among the required ones")
    func conditionalPermissionsRestrictNothing() {
        #expect(DictationRestriction(missing: [.inputMonitoring, .screenRecording]) == nil)
        #expect(DictationRestriction(missing: [.accessibility, .inputMonitoring])?.missing == [.accessibility])
        #expect(DictationRestriction(missing: [.accessibility, .inputMonitoring])?.message == accessibilitySentence)
    }

    @Test(
        "the message says what each missing required permission costs, Microphone first",
        arguments: [
            ([Permission.microphone], microphoneSentence),
            ([.accessibility], accessibilitySentence),
            ([.microphone, .accessibility], "\(microphoneSentence) \(accessibilitySentence)"),
            ([.accessibility, .microphone], "\(microphoneSentence) \(accessibilitySentence)"),
        ]
    )
    func messageSaysWhatIsLost(missing: [Permission], expected: String) {
        let restriction = DictationRestriction(missing: missing)

        #expect(restriction?.missing == missing)
        #expect(restriction?.message == expected)
    }

    @Test(
        "each permission is named as System Settings shows it",
        arguments: [
            (Permission.microphone, "Microphone"),
            (.accessibility, "Accessibility"),
            (.inputMonitoring, "Input Monitoring"),
            (.screenRecording, "Screen Recording"),
        ]
    )
    func displayNames(permission: Permission, expected: String) {
        #expect(permission.displayName == expected)
    }

    @Test("the monitor publishes the same type the menu and the overlay read, from the required permissions only")
    func monitorPublishesIt() async {
        let rig = Rig(
            [.microphone: .denied, .accessibility: .granted, .inputMonitoring: .denied],
            needs: PermissionNeeds(modifierOnlyHotkey: true))

        await rig.monitor.refresh()
        let restriction: DictationRestriction? = rig.monitor.restriction

        #expect(restriction == DictationRestriction(missing: [.microphone]))
    }
}
