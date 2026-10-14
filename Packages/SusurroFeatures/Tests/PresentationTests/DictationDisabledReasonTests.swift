import Domain
import Testing

@testable import Presentation

@MainActor
@Suite("Dictation disabled reason", .timeLimit(.minutes(1)))
struct DictationDisabledReasonTests {
    @Test("nothing blocking means there is no reason")
    func noReasonWhenNothingBlocks() {
        #expect(DictationDisabledReason(blocking: []) == nil)
    }

    @Test(
        "the message names the missing permissions in the order they come",
        arguments: [
            ([Permission.microphone], "Dictation is off until Microphone is allowed."),
            ([.accessibility], "Dictation is off until Accessibility is allowed."),
            ([.microphone, .accessibility], "Dictation is off until Microphone and Accessibility are allowed."),
            ([.accessibility, .microphone], "Dictation is off until Accessibility and Microphone are allowed."),
        ]
    )
    func messageNamesThePermissions(permissions: [Permission], expected: String) {
        let reason = DictationDisabledReason(blocking: permissions)

        #expect(reason?.permissions == permissions)
        #expect(reason?.message == expected)
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
        let reason: DictationDisabledReason? = rig.monitor.disabledReason

        #expect(reason == DictationDisabledReason(blocking: [.microphone]))
    }
}
