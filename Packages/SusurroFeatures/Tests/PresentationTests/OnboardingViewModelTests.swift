import CoreTestSupport
import Domain
import SusurroUI
import Testing

@testable import Presentation

private struct RowCase: Sendable {
    let permission: Permission
    let status: PermissionStatus
    let rowStatus: OnboardingRowStatus
    let action: OnboardingAction.Kind?
    let title: String?
}

@MainActor
@Suite("Onboarding view model", .timeLimit(.minutes(1)))
struct OnboardingViewModelTests {
    private let everything = PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true)

    private func row(_ id: OnboardingPermission, of model: OnboardingViewModel) throws -> OnboardingRowState {
        try #require(model.state.rows.first { $0.id == id })
    }

    // MARK: Rows

    @Test(
        "the rows are the requested permissions, in the order of the onboarding",
        arguments: [
            (PermissionNeeds(), [OnboardingPermission.microphone, .accessibility]),
            (PermissionNeeds(modifierOnlyHotkey: true), [.microphone, .accessibility, .inputMonitoring]),
            (PermissionNeeds(ocrEnabled: true), [.microphone, .accessibility, .screenRecording]),
            (
                PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true),
                [.microphone, .accessibility, .inputMonitoring, .screenRecording]
            ),
        ]
    )
    func rowsAreTheRequestedPermissions(needs: PermissionNeeds, expected: [OnboardingPermission]) {
        let model = OnboardingViewModel(monitor: Rig([:], needs: needs).monitor)

        #expect(model.state.rows.map(\.id) == expected)
    }

    @Test("a row appears when the setup starts to need its permission, and goes when it stops")
    func rowsFollowTheNeeds() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let model = OnboardingViewModel(monitor: rig.monitor)

        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))
        let withOCR = model.state.rows.map(\.id)
        await rig.monitor.setNeeds(PermissionNeeds())

        #expect(withOCR == [.microphone, .accessibility, .screenRecording])
        #expect(model.state.rows.map(\.id) == [.microphone, .accessibility])
    }

    @Test("a row has a title, a reason why the permission is needed, and no two rows say the same")
    func rowsExplainWhy() {
        let model = OnboardingViewModel(monitor: Rig([:], needs: everything).monitor)

        let titles = model.state.rows.map(\.title)
        let reasons = model.state.rows.map(\.why)

        #expect(titles == ["Microphone", "Accessibility", "Input Monitoring", "Screen Recording"])
        #expect(reasons.allSatisfy { !$0.isEmpty })
        #expect(Set(reasons).count == 4)
    }

    @Test("the required rows are not optional, and the conditional rows are optional and say which feature needs them")
    func optionalRowsCarryAFeatureNote() throws {
        let model = OnboardingViewModel(monitor: Rig([:], needs: everything).monitor)

        let microphone = try row(.microphone, of: model)
        let accessibility = try row(.accessibility, of: model)
        let inputMonitoring = try row(.inputMonitoring, of: model)
        let screenRecording = try row(.screenRecording, of: model)

        #expect(!microphone.isOptional)
        #expect(!accessibility.isOptional)
        #expect(microphone.featureNote == nil)
        #expect(accessibility.featureNote == nil)
        #expect(inputMonitoring.isOptional)
        #expect(screenRecording.isOptional)
        #expect(inputMonitoring.featureNote?.contains("modifier") == true)
        #expect(screenRecording.featureNote?.contains("on-screen") == true)
    }

    // MARK: Status and action

    @Test(
        "a row shows how far its permission is and offers the step that fits",
        arguments: [
            RowCase(
                permission: .microphone, status: .notDetermined, rowStatus: .notAsked, action: .request,
                title: "Allow Microphone"),
            RowCase(
                permission: .microphone, status: .denied, rowStatus: .denied, action: .openSettings,
                title: "Open System Settings"),
            RowCase(permission: .microphone, status: .granted, rowStatus: .granted, action: nil, title: nil),
            // Accessibility and Screen Recording report only allowed or not, so a user who was never asked reads as denied
            // and the request, which shows the system prompt that leads to System Settings, comes first.
            RowCase(
                permission: .accessibility, status: .denied, rowStatus: .denied, action: .request,
                title: "Allow Accessibility"),
            RowCase(permission: .accessibility, status: .granted, rowStatus: .granted, action: nil, title: nil),
            RowCase(
                permission: .inputMonitoring, status: .notDetermined, rowStatus: .notAsked, action: .request,
                title: "Allow Input Monitoring"),
            RowCase(
                permission: .inputMonitoring, status: .denied, rowStatus: .denied, action: .openSettings,
                title: "Open System Settings"),
            RowCase(
                permission: .screenRecording, status: .denied, rowStatus: .denied, action: .request,
                title: "Allow Screen Recording"),
        ]
    )
    fileprivate func statusAndAction(_ scenario: RowCase) async throws {
        let rig = Rig([scenario.permission: scenario.status], needs: everything)
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        let shown = try row(OnboardingPermission(scenario.permission), of: model)

        #expect(shown.status == scenario.rowStatus)
        #expect(shown.action?.kind == scenario.action)
        #expect(shown.action?.title == scenario.title)
    }

    @Test("a permission that has not been read yet is shown as not asked")
    func unreadIsNotAsked() throws {
        let model = OnboardingViewModel(monitor: Rig([:]).monitor)

        let shown = try row(.microphone, of: model)

        #expect(shown.status == .notAsked)
        #expect(shown.action?.kind == .request)
    }

    // MARK: Done and the disabled reason

    @Test("Done is off before the statuses are read, and on once nothing blocks dictation")
    func doneEnablesWhenNothingBlocks() async {
        let rig = Rig([.microphone: .denied, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)
        let unread = model.state.isDoneEnabled

        await rig.monitor.refresh()
        let bothMissing = model.state.isDoneEnabled
        rig.board.set(.microphone, to: .granted)
        await rig.monitor.refresh()
        let oneMissing = model.state.isDoneEnabled
        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.refresh()

        #expect(!unread)
        #expect(!bothMissing)
        #expect(!oneMissing)
        #expect(model.state.isDoneEnabled)
        #expect(model.state.dictationDisabledMessage == nil)
    }

    @Test("a denied conditional permission leaves Done on and dictation enabled")
    func conditionalRowsNeverGate() async throws {
        let rig = Rig(
            [.microphone: .granted, .accessibility: .granted, .inputMonitoring: .denied, .screenRecording: .denied],
            needs: everything)
        let model = OnboardingViewModel(monitor: rig.monitor)

        await rig.monitor.refresh()

        #expect(model.state.isDoneEnabled)
        #expect(model.state.dictationDisabledMessage == nil)
        #expect(try row(.inputMonitoring, of: model).status == .denied)
        #expect(try row(.screenRecording, of: model).status == .denied)
    }

    @Test("the visible reason comes from the required permissions only")
    func reasonComesFromBlockingOnly() async {
        let rig = Rig(
            [.microphone: .denied, .accessibility: .granted, .inputMonitoring: .denied, .screenRecording: .denied],
            needs: everything)
        let model = OnboardingViewModel(monitor: rig.monitor)

        await rig.monitor.refresh()

        #expect(model.state.dictationDisabledMessage == "Dictation is off until Microphone is allowed.")
        #expect(!model.state.isDoneEnabled)
    }

    @Test("the reason names both required permissions when both are missing")
    func reasonNamesBoth() async {
        let rig = Rig([.microphone: .denied, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)

        await rig.monitor.refresh()

        #expect(
            model.state.dictationDisabledMessage == "Dictation is off until Microphone and Accessibility are allowed.")
    }

    // MARK: The waiting state

    @Test("while the system prompt is up the row waits and offers nothing")
    func promptUpRowWaits() async throws {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        let model = OnboardingViewModel(monitor: monitor)
        await monitor.refresh()

        let asking = Task { await model.request(.microphone) }
        await checker.requestEntered.wait()
        let whileUp = try row(.microphone, of: model)
        checker.releaseRequest()
        await asking.value

        #expect(whileUp.status == .waiting)
        #expect(whileUp.action == nil)
        #expect(checker.requested == [.microphone])
    }

    @Test("the answer to the prompt ends the waiting")
    func answerEndsTheWaiting() async throws {
        let checker = AnsweringChecker([.microphone: .notDetermined], answering: .granted)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        let model = OnboardingViewModel(monitor: monitor)
        await monitor.refresh()

        await model.request(.microphone)

        #expect(try row(.microphone, of: model).status == .granted)
    }

    @Test("after the request a row that is still denied waits, and offers System Settings, until the status changes")
    func requestThenWaitForSettings() async throws {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        await model.request(.accessibility)
        let waiting = try row(.accessibility, of: model)
        rig.board.set(.accessibility, to: .granted)
        await model.recheck()

        #expect(waiting.status == .waiting)
        #expect(waiting.action?.kind == .openSettings)
        #expect(try row(.accessibility, of: model).status == .granted)
    }

    @Test("opening System Settings makes the row wait")
    func openSettingsWaits() async throws {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        model.openSettings(.microphone)

        let shown = try row(.microphone, of: model)
        #expect(shown.status == .waiting)
        #expect(shown.action?.kind == .openSettings)
    }

    // MARK: Stale grants

    @Test("a row still denied 30 seconds after coming back from System Settings shows the troubleshooting steps")
    func staleRow() async throws {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()
        let before = try row(.accessibility, of: model)
        model.openSettings(.accessibility)

        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { (try? row(.accessibility, of: model).status) == .stale }

        let stale = try row(.accessibility, of: model)
        #expect(before.staleGuidance == nil)
        #expect(stale.status == .stale)
        #expect(stale.action?.kind == .openSettings)
        #expect(stale.staleGuidance?.isEmpty == false)
        #expect(try row(.microphone, of: model).staleGuidance == nil)
    }

    // MARK: Intents

    @Test(
        "an intent reaches the permission it names",
        arguments: [
            (OnboardingPermission.microphone, Permission.microphone),
            (.accessibility, .accessibility),
            (.inputMonitoring, .inputMonitoring),
            (.screenRecording, .screenRecording),
        ]
    )
    func intentsMapToPermissions(named: OnboardingPermission, expected: Permission) async {
        let rig = Rig([:], needs: everything)
        let model = OnboardingViewModel(monitor: rig.monitor)

        await model.request(named)
        model.openSettings(named)

        #expect(rig.board.requested == [expected])
        #expect(rig.panes.opened == [expected])
    }

    @Test("recheck reads the statuses now")
    func recheckReads() async throws {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let model = OnboardingViewModel(monitor: rig.monitor)
        await rig.monitor.refresh()

        rig.board.set(.microphone, to: .granted)
        await model.recheck()

        #expect(try row(.microphone, of: model).status == .granted)
        #expect(model.state.isDoneEnabled)
    }

    @Test("the poll runs while the onboarding is on screen and stops when it goes")
    func pollFollowsTheScreen() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        let model = OnboardingViewModel(monitor: rig.monitor)

        model.onboardingDidAppear()
        await rig.clock.waitForSleeps(1)
        let whileShown = rig.clock.pendingSleeps
        model.onboardingDidDisappear()

        #expect(whileShown == 1)
        #expect(rig.clock.pendingSleeps == 0)
        #expect(model.state.isDoneEnabled)
    }
}
