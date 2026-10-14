import Domain
import Testing

@testable import Presentation

/// The rule that says which step fits a permission, shared by the onboarding and the menu.
@Suite("Permission step", .timeLimit(.minutes(1)))
struct PermissionStepTests {
    private static let followUps: [PermissionsMonitor.FollowUp?] = [nil, .requesting, .sentToSettings, .stale]
    private static let notGranted: [PermissionStatus] = [.notDetermined, .denied]

    @Test(
        "a granted permission has no step, whatever follow-up is left",
        arguments: Permission.allCases, followUps
    )
    func grantedHasNoStep(permission: Permission, followUp: PermissionsMonitor.FollowUp?) {
        let step = PermissionStep.make(permission: permission, status: .granted, followUp: followUp)

        #expect(step == PermissionStep(standing: .granted, action: nil))
    }

    @Test(
        "a request that is open waits for the answer and offers nothing",
        arguments: Permission.allCases, notGranted
    )
    func requestingWaits(permission: Permission, status: PermissionStatus) {
        let step = PermissionStep.make(permission: permission, status: status, followUp: .requesting)

        #expect(step == PermissionStep(standing: .waiting, action: nil))
    }

    @Test(
        "a trip to System Settings waits and offers System Settings again, whatever the status says",
        arguments: Permission.allCases, notGranted
    )
    func sentToSettingsWaits(permission: Permission, status: PermissionStatus) {
        let step = PermissionStep.make(permission: permission, status: status, followUp: .sentToSettings)

        #expect(step == PermissionStep(standing: .waiting, action: .openSettings))
    }

    @Test(
        "a stale follow-up asks for the troubleshooting and offers System Settings",
        arguments: Permission.allCases, notGranted
    )
    func staleOffersSettings(permission: Permission, status: PermissionStatus) {
        let step = PermissionStep.make(permission: permission, status: status, followUp: .stale)

        #expect(step == PermissionStep(standing: .stale, action: .openSettings))
    }

    @Test("a permission nobody has asked for is asked for: the request comes first", arguments: Permission.allCases)
    func notDeterminedIsAsked(permission: Permission) {
        let step = PermissionStep.make(permission: permission, status: .notDetermined, followUp: nil)

        #expect(step == PermissionStep(standing: .notAsked, action: .request))
    }

    @Test(
        "a refusal opens System Settings, except where denied may mean never asked, which asks first",
        arguments: [
            (Permission.microphone, PermissionStep.Action.openSettings),
            (.inputMonitoring, .openSettings),
            (.accessibility, .request),
            (.screenRecording, .request),
        ]
    )
    func deniedOpensSettings(permission: Permission, action: PermissionStep.Action) {
        let step = PermissionStep.make(permission: permission, status: .denied, followUp: nil)

        #expect(step == PermissionStep(standing: .denied, action: action))
    }
}
