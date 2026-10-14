import Testing

@testable import Domain

@Suite("Permission policy", .timeLimit(.minutes(1)))
struct PermissionPolicyTests {
    private static let everythingGranted: [Permission: PermissionStatus] = [
        .microphone: .granted, .accessibility: .granted, .inputMonitoring: .granted, .screenRecording: .granted,
    ]

    @Test("only Microphone and Accessibility are required, whatever the setup")
    func requiredPermissions() {
        #expect(PermissionPolicy.required == [.microphone, .accessibility])
    }

    @Test("a default setup, with a keyed hotkey and OCR off, requests only Microphone and Accessibility")
    func defaultSetup() {
        #expect(PermissionPolicy.conditional(for: PermissionNeeds()).isEmpty)
        #expect(PermissionPolicy.requested(for: PermissionNeeds()) == [.microphone, .accessibility])
    }

    @Test(
        "Input Monitoring is conditional on a modifier-only or fn hotkey, Screen Recording on OCR being on",
        arguments: [
            (false, false, [Permission]()),
            (true, false, [.inputMonitoring]),
            (false, true, [.screenRecording]),
            (true, true, [.inputMonitoring, .screenRecording]),
        ]
    )
    func conditionalPermissions(modifierOnlyHotkey: Bool, ocrEnabled: Bool, expected: [Permission]) {
        let needs = PermissionNeeds(modifierOnlyHotkey: modifierOnlyHotkey, ocrEnabled: ocrEnabled)

        #expect(PermissionPolicy.conditional(for: needs) == expected)
        #expect(PermissionPolicy.requested(for: needs) == PermissionPolicy.required + expected)
    }

    @Test("the permissions are listed in the order the onboarding shows them")
    func order() {
        #expect(Permission.allCases == [.microphone, .accessibility, .inputMonitoring, .screenRecording])
    }

    @Test("with every required permission granted nothing is missing and the onboarding is complete")
    func allGranted() {
        let needs = PermissionNeeds()

        #expect(PermissionPolicy.missing(for: needs, statuses: Self.everythingGranted).isEmpty)
        #expect(PermissionPolicy.blocking(statuses: Self.everythingGranted).isEmpty)
        #expect(PermissionPolicy.isOnboardingComplete(statuses: Self.everythingGranted))
    }

    @Test(
        "a required permission that is denied or not determined is missing, and the onboarding is not complete",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func oneMissing(status: PermissionStatus) {
        var statuses = Self.everythingGranted
        statuses[.accessibility] = status

        #expect(PermissionPolicy.missing(for: PermissionNeeds(), statuses: statuses) == [.accessibility])
        #expect(PermissionPolicy.blocking(statuses: statuses) == [.accessibility])
        #expect(!PermissionPolicy.isOnboardingComplete(statuses: statuses))
    }

    @Test("a permission nobody has read yet counts as missing, so a Mac is never taken for ready by default")
    func unreadIsMissing() {
        let statuses: [Permission: PermissionStatus] = [.microphone: .granted]

        #expect(PermissionPolicy.missing(for: PermissionNeeds(), statuses: statuses) == [.accessibility])
        #expect(PermissionPolicy.blocking(statuses: statuses) == [.accessibility])
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
        "a permission the setup does not request is not missing, whatever its status",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func unrequestedPermissionsAreIgnored(status: PermissionStatus) {
        var statuses = Self.everythingGranted
        statuses[.inputMonitoring] = status
        statuses[.screenRecording] = status

        #expect(PermissionPolicy.missing(for: PermissionNeeds(), statuses: statuses).isEmpty)
        #expect(PermissionPolicy.isOnboardingComplete(statuses: statuses))
    }

    @Test(
        "a new need shows up as missing, but the onboarding stays complete because a conditional permission never gates"
    )
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
        #expect(PermissionPolicy.blocking(statuses: statuses).isEmpty)
        #expect(PermissionPolicy.isOnboardingComplete(statuses: statuses))
    }

    @Test(
        "with OCR on and Screen Recording denied, the onboarding is complete and the permission does not block",
        arguments: [PermissionStatus.denied, .notDetermined]
    )
    func deniedConditionalDoesNotBlock(status: PermissionStatus) {
        let needs = PermissionNeeds(ocrEnabled: true)
        var statuses = Self.everythingGranted
        statuses[.screenRecording] = status

        #expect(PermissionPolicy.missing(for: needs, statuses: statuses) == [.screenRecording])
        #expect(PermissionPolicy.blocking(statuses: statuses).isEmpty)
        #expect(PermissionPolicy.isOnboardingComplete(statuses: statuses))
    }

    @Test("a required permission blocks even while a conditional one is also missing, and is the only one that does")
    func blockingIsRequiredOnly() {
        let needs = PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true)
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .denied, .accessibility: .granted, .inputMonitoring: .denied, .screenRecording: .denied,
        ]

        #expect(
            PermissionPolicy.missing(for: needs, statuses: statuses) == [
                .microphone, .inputMonitoring, .screenRecording,
            ])
        #expect(PermissionPolicy.blocking(statuses: statuses) == [.microphone])
        #expect(!PermissionPolicy.isOnboardingComplete(statuses: statuses))
    }

    @Test(
        "the onboarding is complete when everything is granted, comes back when one is revoked, and ends when it returns"
    )
    func revocationAndRegrant() {
        var statuses = Self.everythingGranted
        let atLaunch = PermissionPolicy.isOnboardingComplete(statuses: statuses)

        statuses[.microphone] = .denied
        let afterRevocation = PermissionPolicy.isOnboardingComplete(statuses: statuses)
        statuses[.microphone] = .granted
        let afterRegrant = PermissionPolicy.isOnboardingComplete(statuses: statuses)

        #expect(atLaunch)
        #expect(!afterRevocation)
        #expect(afterRegrant)
    }
}
