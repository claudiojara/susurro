import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation
@testable import SusurroUI

/// `SusurroUI` cannot read the words of the app, which are in `SusurroFeatures`, so its previews and snapshot tests carry
/// fixtures with the words written out. These tests keep them from drifting: each fixture is the state or the row that the
/// view model builds for the same permissions, down to the last word.
@MainActor
@Suite("Onboarding fixtures", .timeLimit(.minutes(1)))
struct OnboardingFixturesTests {
    private struct RowCase: Sendable, CustomTestStringConvertible {
        let fixture: OnboardingFixtures.Row
        let permission: Permission
        let status: PermissionStatus
        let followUp: PermissionsMonitor.FollowUp?

        var testDescription: String { "\(fixture)" }
    }

    @Test(
        "each fixture row is the row the view model builds for its permission, status, and follow-up",
        arguments: [
            RowCase(fixture: .granted, permission: .microphone, status: .granted, followUp: nil),
            RowCase(fixture: .notAsked, permission: .microphone, status: .notDetermined, followUp: nil),
            RowCase(fixture: .denied, permission: .microphone, status: .denied, followUp: nil),
            RowCase(fixture: .waitingForPrompt, permission: .accessibility, status: .denied, followUp: .requesting),
            RowCase(
                fixture: .waitingInSettings, permission: .accessibility, status: .denied, followUp: .sentToSettings),
            RowCase(fixture: .stale, permission: .accessibility, status: .denied, followUp: .stale),
            RowCase(fixture: .optional, permission: .inputMonitoring, status: .notDetermined, followUp: nil),
        ]
    )
    fileprivate func rowsAreTheRealOnes(_ scenario: RowCase) {
        let real = OnboardingViewModel.row(
            for: scenario.permission, status: scenario.status, followUp: scenario.followUp)

        #expect(OnboardingFixtures.row(scenario.fixture) == real)
    }

    @Test("the fixture rows cover every status a row can show, so none of its words is left unchecked")
    func fixturesCoverTheStatuses() {
        let statuses = OnboardingFixtures.Row.allCases.map { OnboardingFixtures.row($0).statusText }

        #expect(Set(statuses) == ["Allowed", "Not asked yet", "Not allowed", "Waiting…", "Needs attention"])
    }

    @Test("the fresh-install screen is the state of the view model before anything is allowed")
    func freshScreen() async {
        let rig = Rig([.microphone: .notDetermined, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        #expect(OnboardingFixtures.state(.fresh) == model.state)
    }

    @Test("the all-allowed screen is the state of the view model when both required permissions are granted")
    func allGrantedScreen() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        #expect(OnboardingFixtures.state(.allGranted) == model.state)
    }

    @Test("the stale screen is the state of the view model when Accessibility did not change after Settings")
    func staleScreen() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }

        #expect(OnboardingFixtures.state(.stale) == model.state)
    }

    @Test("the screen with the optional rows is the state of the view model when the setup uses all four permissions")
    func withOptionalScreen() async {
        let rig = Rig(
            [
                .microphone: .granted, .accessibility: .granted, .inputMonitoring: .notDetermined,
                .screenRecording: .notDetermined,
            ],
            needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        #expect(OnboardingFixtures.state(.withOptional) == model.state)
    }
}
