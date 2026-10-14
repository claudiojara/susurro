import Testing

@testable import Domain

@Suite("Permission policy", .timeLimit(.minutes(1)))
struct PermissionPolicyTests {
    private static let everythingGranted: [Permission: PermissionStatus] = [
        .microphone: .granted, .accessibility: .granted, .inputMonitoring: .granted, .screenRecording: .granted,
    ]

    @Test("a default setup, with a keyed hotkey and OCR off, needs only Microphone and Accessibility")
    func defaultSetup() {
        #expect(PermissionPolicy.required(for: PermissionNeeds()) == [.microphone, .accessibility])
    }

    @Test(
        "Input Monitoring is needed only for a modifier-only or fn hotkey, Screen Recording only with OCR on",
        arguments: [
            (false, false, [Permission.microphone, .accessibility]),
            (true, false, [.microphone, .accessibility, .inputMonitoring]),
            (false, true, [.microphone, .accessibility, .screenRecording]),
            (true, true, [.microphone, .accessibility, .inputMonitoring, .screenRecording]),
        ]
    )
    func conditionalPermissions(modifierOnlyHotkey: Bool, ocrEnabled: Bool, expected: [Permission]) {
        let needs = PermissionNeeds(modifierOnlyHotkey: modifierOnlyHotkey, ocrEnabled: ocrEnabled)

        #expect(PermissionPolicy.required(for: needs) == expected)
    }

    @Test("the permissions are listed in the order the onboarding shows them")
    func order() {
        #expect(Permission.allCases == [.microphone, .accessibility, .inputMonitoring, .screenRecording])
    }

    @Test("with every required permission granted nothing is missing and the onboarding is complete")
    func allGranted() {
        let needs = PermissionNeeds()

        #expect(PermissionPolicy.missing(for: needs, statuses: Self.everythingGranted).isEmpty)
        #expect(PermissionPolicy.isOnboardingComplete(for: needs, statuses: Self.everythingGranted))
    }

    @Test(
        "a required permission that is denied or not determined is missing, and the onboarding is not complete",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func oneMissing(status: PermissionStatus) {
        var statuses = Self.everythingGranted
        statuses[.accessibility] = status

        #expect(PermissionPolicy.missing(for: PermissionNeeds(), statuses: statuses) == [.accessibility])
        #expect(!PermissionPolicy.isOnboardingComplete(for: PermissionNeeds(), statuses: statuses))
    }

    @Test("a permission nobody has read yet counts as missing, so a Mac is never taken for ready by default")
    func unreadIsMissing() {
        let statuses: [Permission: PermissionStatus] = [.microphone: .granted]

        #expect(PermissionPolicy.missing(for: PermissionNeeds(), statuses: statuses) == [.accessibility])
    }

    @Test("every missing permission is listed, in the order of the policy")
    func missingKeepsThePolicyOrder() {
        let needs = PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true)
        let statuses: [Permission: PermissionStatus] = [.microphone: .denied, .accessibility: .granted]

        #expect(
            PermissionPolicy.missing(for: needs, statuses: statuses)
                == [.microphone, .inputMonitoring, .screenRecording]
        )
    }

    @Test(
        "a permission the setup does not need cannot hold the onboarding back, whatever its status",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func unneededPermissionsAreIgnored(status: PermissionStatus) {
        var statuses = Self.everythingGranted
        statuses[.inputMonitoring] = status
        statuses[.screenRecording] = status

        #expect(PermissionPolicy.isOnboardingComplete(for: PermissionNeeds(), statuses: statuses))
    }

    @Test("turning on a hotkey or OCR that needs a permission brings the onboarding back until it is granted")
    func newNeedMakesAPermissionMissing() {
        var statuses = Self.everythingGranted
        statuses[.inputMonitoring] = .denied
        statuses[.screenRecording] = .notDetermined

        #expect(
            PermissionPolicy.missing(for: PermissionNeeds(modifierOnlyHotkey: true), statuses: statuses)
                == [.inputMonitoring]
        )
        #expect(
            PermissionPolicy.missing(for: PermissionNeeds(ocrEnabled: true), statuses: statuses)
                == [.screenRecording]
        )
    }

    @Test(
        "the onboarding is complete when everything is granted, comes back when one is revoked, and ends when it returns"
    )
    func revocationAndRegrant() {
        let needs = PermissionNeeds()
        var statuses = Self.everythingGranted
        let atLaunch = PermissionPolicy.isOnboardingComplete(for: needs, statuses: statuses)

        statuses[.microphone] = .denied
        let afterRevocation = PermissionPolicy.isOnboardingComplete(for: needs, statuses: statuses)
        statuses[.microphone] = .granted
        let afterRegrant = PermissionPolicy.isOnboardingComplete(for: needs, statuses: statuses)

        #expect(atLaunch)
        #expect(!afterRevocation)
        #expect(afterRegrant)
    }
}
