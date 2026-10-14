import CoreTestSupport
import Domain
import Synchronization
import Testing

@testable import Presentation

/// Holds the first status read until the test releases it, and then answers with the old value. Every later read gets
/// the new one. It is how a slow read ends up running past a newer one.
private final class SlowFirstReadChecker: PermissionsChecker {
    let firstReadEntered = Gate()
    let releaseFirstRead = Gate()
    private let reads = Mutex(0)

    func status(_ permission: Permission) async -> PermissionStatus {
        let number = reads.withLock { reads in
            defer { reads += 1 }
            return reads
        }
        guard number == 0 else { return .granted }
        firstReadEntered.open()
        await releaseFirstRead.wait()
        return .denied
    }

    func request(_ permission: Permission) async {}
}

@MainActor
@Suite("Permissions monitor", .timeLimit(.minutes(1)))
struct PermissionsMonitorTests {
    // MARK: Reading

    @Test("refresh publishes the status of each requested permission and reads no other")
    func refreshReadsTheRequestedPermissions() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied, .inputMonitoring: .granted])

        await rig.monitor.refresh()

        #expect(rig.monitor.statuses == [.microphone: .granted, .accessibility: .denied])
        #expect(rig.board.statusReads == 2)
    }

    @Test("a setup that uses a modifier-only hotkey and OCR reads Input Monitoring and Screen Recording too")
    func conditionalPermissionsAreRead() async {
        let rig = Rig(
            [.microphone: .granted, .accessibility: .granted, .inputMonitoring: .denied],
            needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))

        await rig.monitor.refresh()

        #expect(
            rig.monitor.statuses == [
                .microphone: .granted, .accessibility: .granted, .inputMonitoring: .denied,
                .screenRecording: .notDetermined,
            ])
        #expect(rig.monitor.requested == Permission.allCases)
        #expect(rig.board.statusReads == 4)
    }

    @Test("a new need is read at once, without waiting for the next poll")
    func newNeedIsRead() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted, .screenRecording: .denied])
        await rig.monitor.refresh()

        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))

        #expect(rig.monitor.statuses[.screenRecording] == .denied)
        #expect(rig.monitor.requested == [.microphone, .accessibility, .screenRecording])
        #expect(rig.board.statusReads == 5)
    }

    @Test("nothing is known before the first read, so the onboarding is not asked for until then")
    func nothingReadYet() async {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let before = (rig.monitor.hasReadStatuses, rig.monitor.needsOnboarding, rig.monitor.statuses)

        await rig.monitor.refresh()

        #expect(before.0 == false)
        #expect(before.1 == false)
        #expect(before.2.isEmpty)
        #expect(rig.monitor.hasReadStatuses)
        #expect(rig.monitor.needsOnboarding)
    }

    @Test("a read that finishes after a newer one does not put its older statuses back")
    func olderReadIsDropped() async {
        let checker = SlowFirstReadChecker()
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        let slow = Task { await monitor.refresh() }
        await checker.firstReadEntered.wait()

        await monitor.refresh()
        checker.releaseFirstRead.open()
        await slow.value

        #expect(monitor.statuses == [.microphone: .granted, .accessibility: .granted])
    }

    // MARK: Polling

    @Test("once started, the statuses are read at once and then every second")
    func pollsEverySecond() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])

        rig.monitor.start()
        await rig.clock.waitForSleeps(1)
        let afterTheFirstRead = rig.board.statusReads
        rig.board.set(.accessibility, to: .granted)
        rig.clock.advance(by: .milliseconds(999))
        let justBeforeTheSecond = rig.board.statusReads
        rig.clock.advance(by: .milliseconds(1))
        await rig.clock.waitForSleeps(2)

        #expect(afterTheFirstRead == 2)
        #expect(justBeforeTheSecond == 2)
        #expect(rig.board.statusReads == 4)
        // The grant made in System Settings shows within the second, without a relaunch.
        #expect(rig.monitor.statuses[.accessibility] == .granted)

        rig.clock.advance(by: .seconds(1))
        await rig.clock.waitForSleeps(3)

        #expect(rig.board.statusReads == 6)
    }

    @Test("a monitor that was not started reads nothing on a timer")
    func silentUntilStarted() async {
        let rig = Rig([.microphone: .granted])

        rig.clock.advance(by: .seconds(30))
        await rig.settle()

        #expect(rig.board.statusReads == 0)
        #expect(rig.clock.suspendedSleeps == 0)
    }

    @Test("a permission revoked while the app idles is found within the second, with no activation and no screen open")
    func revocationWithoutActivation() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        rig.monitor.start()
        await rig.clock.waitForSleeps(1)
        let beforeTheRevoke = (rig.monitor.restriction, rig.monitor.needsOnboarding)

        rig.board.set(.accessibility, to: .denied)
        rig.clock.advance(by: .milliseconds(999))
        await rig.settle()
        let justBeforeTheSecond = rig.monitor.restriction
        rig.clock.advance(by: .milliseconds(1))
        await rig.clock.waitForSleeps(2)

        #expect(beforeTheRevoke.0 == nil)
        #expect(beforeTheRevoke.1 == false)
        #expect(justBeforeTheSecond == nil)
        #expect(rig.monitor.restriction?.missing == [.accessibility])
        #expect(rig.monitor.needsOnboarding)
    }

    @Test("stopping the monitor ends the poll, and starting it again resumes it")
    func pollFollowsStartAndStop() async {
        let rig = Rig([.microphone: .granted])
        rig.monitor.start()
        await rig.clock.waitForSleeps(1)

        rig.monitor.stop()
        let pendingWhenStopped = rig.clock.pendingSleeps
        rig.clock.advance(by: .seconds(10))
        await rig.settle()
        let readsWhenStopped = rig.board.statusReads
        rig.monitor.start()
        await rig.clock.waitForSleeps(2)

        #expect(pendingWhenStopped == 0)
        #expect(readsWhenStopped == 2)
        #expect(rig.board.statusReads == 4)
        #expect(rig.clock.pendingSleeps == 1)
    }

    @Test("starting the monitor twice does not start a second poll")
    func onePollAtATime() async {
        let rig = Rig([.microphone: .granted])

        rig.monitor.start()
        rig.monitor.start()
        await rig.clock.waitForSleeps(1)
        await rig.settle()
        let whileSleeping = (rig.board.statusReads, rig.clock.pendingSleeps)
        rig.monitor.start()
        await rig.settle()

        #expect(whileSleeping.0 == 2)
        #expect(whileSleeping.1 == 1)
        // A start while the poll sleeps neither reads at once nor begins another loop.
        #expect(rig.board.statusReads == 2)
        #expect(rig.clock.pendingSleeps == 1)
    }

    @Test("becoming the active app reads the statuses, also while the onboarding is hidden")
    func activationReads() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])

        await rig.monitor.appDidBecomeActive()

        #expect(rig.monitor.statuses == [.microphone: .granted, .accessibility: .denied])
        #expect(rig.clock.suspendedSleeps == 0)
    }

    @Test("each activation the app reports is a return to the app: a read, and the wait for stale guidance")
    func activationStream() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let (activations, continuation) = AsyncStream.makeStream(of: Void.self)
        let running = Task { await rig.monitor.run(activations: activations) }

        continuation.yield()
        await waitUntil { rig.monitor.statuses[.accessibility] == .denied }
        rig.monitor.openSettings(for: .accessibility)
        continuation.yield()
        await rig.clock.waitForSleeps(1)
        rig.board.set(.accessibility, to: .granted)
        continuation.yield()
        await waitUntil { rig.monitor.statuses[.accessibility] == .granted }
        continuation.finish()
        await running.value

        #expect(rig.board.statusReads == 6)
        #expect(rig.clock.pendingSleeps == 0)
    }

    // MARK: Revocation and the restriction

    @Test("a permission revoked while the app runs is published as denied and restricts dictation with a reason")
    func revocation() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()
        let before = (rig.monitor.restriction, rig.monitor.needsOnboarding)

        rig.board.set(.microphone, to: .denied)
        await rig.monitor.appDidBecomeActive()

        #expect(before.0 == nil)
        #expect(before.1 == false)
        #expect(rig.monitor.statuses[.microphone] == .denied)
        #expect(rig.monitor.blocking == [.microphone])
        #expect(rig.monitor.restriction?.missing == [.microphone])
        #expect(rig.monitor.needsOnboarding)
    }

    @Test("Accessibility revoked does not block recording: the onboarding returns and the restriction says clipboard")
    func accessibilityRevoked() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()

        rig.board.set(.accessibility, to: .denied)
        await rig.monitor.appDidBecomeActive()

        #expect(rig.monitor.statuses[.accessibility] == .denied)
        #expect(rig.monitor.blocking.isEmpty)
        #expect(rig.monitor.missingRequired == [.accessibility])
        #expect(rig.monitor.restriction?.missing == [.accessibility])
        #expect(
            rig.monitor.restriction?.message
                == "Dictated text goes to the clipboard until Accessibility is allowed.")
        #expect(!rig.monitor.isOnboardingComplete)
        #expect(rig.monitor.needsOnboarding)
    }

    @Test(
        "the restriction names every missing required permission, in the order of the onboarding, and only Microphone blocks",
        arguments: [
            (
                [Permission.microphone: PermissionStatus.denied, .accessibility: .denied],
                [Permission.microphone, .accessibility], [Permission.microphone],
                "Dictation is off until Microphone is allowed. "
                    + "Dictated text goes to the clipboard until Accessibility is allowed."
            ),
            (
                [.microphone: .granted, .accessibility: .notDetermined], [.accessibility], [],
                "Dictated text goes to the clipboard until Accessibility is allowed."
            ),
            (
                [.microphone: .notDetermined, .accessibility: .granted], [.microphone], [.microphone],
                "Dictation is off until Microphone is allowed."
            ),
        ]
    )
    func restrictionNamesTheMissingOnes(
        statuses: [Permission: PermissionStatus], missing: [Permission], blocking: [Permission], message: String
    ) async {
        let rig = Rig(statuses)

        await rig.monitor.refresh()

        #expect(rig.monitor.restriction?.missing == missing)
        #expect(rig.monitor.restriction?.message == message)
        #expect(rig.monitor.missingRequired == missing)
        #expect(rig.monitor.blocking == blocking)
    }

    @Test("a denied or unread conditional permission neither disables dictation nor brings the onboarding back")
    func conditionalPermissionNeverGates() async {
        for status in [PermissionStatus.denied, .notDetermined] {
            let rig = Rig(
                [.microphone: .granted, .accessibility: .granted, .inputMonitoring: status, .screenRecording: status],
                needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))

            await rig.monitor.refresh()

            #expect(rig.monitor.statuses[.screenRecording] == status)
            #expect(rig.monitor.restriction == nil)
            #expect(rig.monitor.blocking.isEmpty)
            #expect(rig.monitor.missingRequired.isEmpty)
            #expect(rig.monitor.isOnboardingComplete)
            #expect(!rig.monitor.needsOnboarding)
        }
    }

    @Test("no restriction is given before the first read, when nothing is known yet, and it is given after")
    func noRestrictionBeforeTheFirstRead() async {
        let rig = Rig([.microphone: .denied, .accessibility: .granted])
        let before = (rig.monitor.restriction, rig.monitor.blocking, rig.monitor.missingRequired)

        await rig.monitor.refresh()

        #expect(before.0 == nil)
        // An unread permission is missing, so only the restriction waits for the first read.
        #expect(before.1 == [.microphone])
        #expect(before.2 == [.microphone, .accessibility])
        #expect(rig.monitor.restriction?.missing == [.microphone])
    }

    @Test("a missing required permission is the restriction even when the conditional ones are missing too")
    func restrictionIgnoresConditionalPermissions() async {
        let rig = Rig(
            [.microphone: .denied, .accessibility: .granted, .inputMonitoring: .denied, .screenRecording: .denied],
            needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))

        await rig.monitor.refresh()

        #expect(rig.monitor.restriction?.missing == [.microphone])
    }

    @Test(
        "the onboarding is not needed at launch when both required permissions are granted, and comes back on a revoke")
    func onboardingCompletion() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()
        let atLaunch = rig.monitor.needsOnboarding

        rig.board.set(.microphone, to: .denied)
        await rig.monitor.refresh()
        let afterTheRevoke = rig.monitor.needsOnboarding
        rig.board.set(.microphone, to: .granted)
        await rig.monitor.refresh()

        #expect(atLaunch == false)
        #expect(afterTheRevoke)
        #expect(!rig.monitor.needsOnboarding)
    }

    @Test("a need that goes away stops being read, and the same need again reads nothing")
    func needThatGoesAwayIsDropped() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted, .screenRecording: .denied])
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))
        let withOCR = rig.monitor.statuses.keys.sorted { $0.displayName < $1.displayName }
        let readsWithOCR = rig.board.statusReads
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))
        let readsAfterTheSameNeed = rig.board.statusReads

        await rig.monitor.setNeeds(PermissionNeeds())

        #expect(withOCR == [.accessibility, .microphone, .screenRecording])
        #expect(readsAfterTheSameNeed == readsWithOCR)
        #expect(rig.monitor.statuses == [.microphone: .granted, .accessibility: .granted])
        #expect(rig.monitor.requested == [.microphone, .accessibility])
    }

    @Test("a monitor that is let go also ends its poll")
    func letGoEndsThePoll() async {
        let clock = ManualClock()
        var monitor: PermissionsMonitor? = PermissionsMonitor(
            checker: MutablePermissionsChecker([.microphone: .granted]), openSettings: { _ in }, clock: clock)
        monitor?.start()
        await clock.waitForSleeps(1)

        monitor = nil
        clock.advance(by: .seconds(1))
        for _ in 0..<20 { await Task.yield() }

        #expect(clock.pendingSleeps == 0)
        #expect(clock.suspendedSleeps == 1)
    }

    // MARK: Diagnostics

    @Test(
        "the first read and every change of a status are recorded, a revocation among them, and an unchanged read is not"
    )
    func statusChangesAreRecorded() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])

        await rig.monitor.refresh()
        let firstRead = rig.diagnostics.events
        await rig.monitor.refresh()
        let unchanged = rig.diagnostics.events
        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.refresh()
        rig.board.set(.microphone, to: .denied)
        await rig.monitor.refresh()

        #expect(
            firstRead == [
                .permissionStatusChanged(permission: .microphone, from: nil, to: .granted),
                .permissionStatusChanged(permission: .accessibility, from: nil, to: .denied),
            ])
        #expect(unchanged == firstRead)
        #expect(
            rig.diagnostics.events.dropFirst(2) == [
                .permissionStatusChanged(permission: .accessibility, from: .denied, to: .granted),
                .permissionStatusChanged(permission: .microphone, from: .granted, to: .denied),
            ])
    }

    @Test("the troubleshooting steps being shown is recorded once, when they show and not before")
    func guidanceShownIsRecorded() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        let whileCounting = rig.diagnostics.events.contains(.permissionGuidanceShown(permission: .accessibility))

        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }
        await rig.monitor.appDidBecomeActive()

        #expect(!whileCounting)
        #expect(
            rig.diagnostics.events.filter { $0 == .permissionGuidanceShown(permission: .accessibility) }.count == 1)
    }

    @Test("the outcome of a request is recorded after the status it left, and a refused request records nothing")
    func requestOutcomeIsRecorded() async {
        let checker = AnsweringChecker([.microphone: .notDetermined, .accessibility: .granted], answering: .denied)
        let diagnostics = RecordingDiagnostics()
        let monitor = PermissionsMonitor(
            checker: checker, openSettings: { _ in }, clock: ManualClock(), diagnostics: diagnostics)
        await monitor.refresh()

        await monitor.request(.screenRecording)
        let refused = diagnostics.events.count
        await monitor.request(.microphone)

        #expect(refused == 2)
        #expect(
            diagnostics.events.dropFirst(2) == [
                .permissionStatusChanged(permission: .microphone, from: .notDetermined, to: .denied),
                .permissionRequestEnded(permission: .microphone, status: .denied),
            ])
    }

    // MARK: Requests, Settings, and the waiting state

    @Test("a request asks the system and shows the permission as waiting while its prompt is up")
    func requestWaitsForTheAnswer() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        await monitor.refresh()
        let before = monitor.followUps

        let asking = Task { await monitor.request(.microphone) }
        await checker.requestEntered.wait()
        let whileThePromptIsUp = monitor.followUps
        checker.releaseRequest()
        await asking.value

        #expect(before.isEmpty)
        #expect(whileThePromptIsUp == [.microphone: .requesting])
        #expect(checker.requested == [.microphone])
    }

    @Test("a request does not ask again while its prompt is up")
    func requestIsNotRepeated() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
        let asking = Task { await monitor.request(.microphone) }
        await checker.requestEntered.wait()

        await monitor.request(.microphone)
        checker.releaseRequest()
        await asking.value

        #expect(checker.requested == [.microphone])
    }

    @Test("the answer ends the waiting: granted or denied, the status changed")
    func answerEndsTheWaiting() async {
        for answer in [PermissionStatus.granted, .denied] {
            let checker = AnsweringChecker([.microphone: .notDetermined], answering: answer)
            let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())
            await monitor.refresh()

            await monitor.request(.microphone)

            #expect(monitor.statuses[.microphone] == answer)
            #expect(monitor.followUps.isEmpty)
        }
    }

    @Test("a request made before the first read ends with the answer too")
    func requestBeforeTheFirstRead() async {
        let checker = AnsweringChecker([.microphone: .notDetermined], answering: .denied)
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: ManualClock())

        await monitor.request(.microphone)

        #expect(monitor.statuses[.microphone] == .denied)
        #expect(monitor.followUps.isEmpty)
    }

    @Test("a permission whose status did not change after the request stays waiting until it does")
    func unchangedStatusKeepsWaiting() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()

        await rig.monitor.request(.accessibility)
        await rig.monitor.refresh()
        let whileDenied = rig.monitor.followUps
        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.refresh()

        #expect(rig.board.requested == [.accessibility])
        #expect(whileDenied == [.accessibility: .sentToSettings])
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("a permission that is already granted is not requested")
    func grantedIsNotRequested() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()

        await rig.monitor.request(.microphone)

        #expect(rig.board.requested.isEmpty)
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("opening System Settings opens the pane of the permission and waits for the status to change")
    func openSettingsWaits() async {
        let rig = Rig([.microphone: .denied, .accessibility: .denied])
        await rig.monitor.refresh()

        rig.monitor.openSettings(for: .accessibility)
        rig.monitor.openSettings(for: .microphone)

        #expect(rig.panes.opened == [.accessibility, .microphone])
        #expect(rig.monitor.followUps == [.accessibility: .sentToSettings, .microphone: .sentToSettings])
    }

    @Test("a request can be made again once the first one is over")
    func requestCanBeRepeated() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()

        await rig.monitor.request(.accessibility)
        await rig.monitor.request(.accessibility)

        #expect(rig.board.requested == [.accessibility, .accessibility])
        // A follow-up only moves forward: the second request does not take it back to the prompt.
        #expect(rig.monitor.followUps == [.accessibility: .sentToSettings])
    }

    @Test("opening System Settings for a permission that is granted waits for nothing")
    func openSettingsForGranted() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()

        rig.monitor.openSettings(for: .accessibility)

        #expect(rig.panes.opened == [.accessibility])
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("a permission the setup does not use is not requested, and nothing waits for it until the setup uses it")
    func unneededPermissionIsNotRequested() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted, .screenRecording: .denied])
        await rig.monitor.refresh()

        await rig.monitor.request(.screenRecording)
        await rig.monitor.request(.inputMonitoring)
        let whileUnneeded = (rig.board.requested, rig.monitor.followUps)
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))
        await rig.monitor.request(.screenRecording)

        #expect(whileUnneeded.0.isEmpty)
        #expect(whileUnneeded.1.isEmpty)
        #expect(rig.board.requested == [.screenRecording])
        #expect(rig.monitor.followUps == [.screenRecording: .sentToSettings])
    }

    @Test("System Settings is not opened for a permission the setup does not use, and is once it does")
    func unneededPermissionOpensNoPane() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted, .screenRecording: .denied])
        await rig.monitor.refresh()

        rig.monitor.openSettings(for: .screenRecording)
        let whileUnneeded = (rig.panes.opened, rig.monitor.followUps)
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))
        rig.monitor.openSettings(for: .screenRecording)

        #expect(whileUnneeded.0.isEmpty)
        #expect(whileUnneeded.1.isEmpty)
        #expect(rig.panes.opened == [.screenRecording])
    }

    // MARK: Stale grants

    @Test("a permission still denied 30 seconds after the user came back from System Settings gets the troubleshooting")
    func staleAfterThirtySeconds() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)

        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .milliseconds(29_999))
        await rig.settle()
        let justBefore = rig.monitor.followUps
        rig.clock.advance(by: .milliseconds(1))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }

        #expect(justBefore == [.accessibility: .sentToSettings])
        #expect(rig.monitor.followUps == [.accessibility: .stale])
    }

    @Test("a permission the user is waiting on but that is not denied gets the troubleshooting too")
    func staleWithoutDenied() async {
        // The system can answer a request at once and leave the status as it was, as Input Monitoring does.
        let rig = Rig(
            [.microphone: .granted, .accessibility: .granted, .inputMonitoring: .notDetermined],
            needs: PermissionNeeds(modifierOnlyHotkey: true))
        await rig.monitor.refresh()
        await rig.monitor.request(.inputMonitoring)
        let afterTheRequest = rig.monitor.followUps

        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.inputMonitoring] == .stale }

        #expect(afterTheRequest == [.inputMonitoring: .sentToSettings])
        #expect(rig.monitor.followUps == [.inputMonitoring: .stale])
    }

    @Test("opening System Settings again while the troubleshooting is shown keeps it")
    func staleSurvivesAnotherTrip() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }

        rig.monitor.openSettings(for: .accessibility)

        #expect(rig.panes.opened == [.accessibility, .accessibility])
        #expect(rig.monitor.followUps == [.accessibility: .stale])
    }

    @Test("a permission the setup stops using stops being followed: its wait and its timer end")
    func droppedNeedEndsTheWait() async {
        let rig = Rig(
            [.microphone: .granted, .accessibility: .granted, .screenRecording: .denied],
            needs: PermissionNeeds(ocrEnabled: true))
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .screenRecording)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        let whileCounting = (rig.monitor.followUps, rig.clock.pendingSleeps)

        await rig.monitor.setNeeds(PermissionNeeds())
        let afterTheDrop = (rig.monitor.followUps, rig.clock.pendingSleeps)
        rig.clock.advance(by: .seconds(60))
        await rig.settle()
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))

        #expect(whileCounting.0 == [.screenRecording: .sentToSettings])
        #expect(whileCounting.1 == 1)
        #expect(afterTheDrop.0.isEmpty)
        #expect(afterTheDrop.1 == 0)
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("a permission the setup stops using loses its troubleshooting, which does not come back with the need")
    func droppedNeedEndsTheTroubleshooting() async {
        let rig = Rig(
            [.microphone: .granted, .accessibility: .granted, .screenRecording: .denied],
            needs: PermissionNeeds(ocrEnabled: true))
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .screenRecording)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.screenRecording] == .stale }

        await rig.monitor.setNeeds(PermissionNeeds())
        let afterTheDrop = rig.monitor.followUps
        await rig.monitor.setNeeds(PermissionNeeds(ocrEnabled: true))

        #expect(afterTheDrop.isEmpty)
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("the bounded time is a setting of the monitor")
    func staleTimeIsInjected() async {
        let board = MutablePermissionsChecker([.microphone: .granted, .accessibility: .denied])
        let clock = ManualClock()
        let monitor = PermissionsMonitor(
            checker: board, openSettings: { _ in }, clock: clock, staleAfter: .seconds(5))
        await monitor.refresh()
        monitor.openSettings(for: .accessibility)

        await monitor.appDidBecomeActive()
        await clock.waitForSleeps(1)
        clock.advance(by: .seconds(5))
        await waitUntil { monitor.followUps[.accessibility] == .stale }

        #expect(monitor.followUps == [.accessibility: .stale])
    }

    @Test("the time counts from the return, not from opening System Settings")
    func timeCountsFromTheReturn() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()

        rig.monitor.openSettings(for: .accessibility)
        await rig.settle()
        rig.clock.advance(by: .seconds(60))
        await rig.settle()
        let whileAway = rig.monitor.followUps
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(29))
        await rig.settle()

        #expect(whileAway == [.accessibility: .sentToSettings])
        #expect(rig.monitor.followUps == [.accessibility: .sentToSettings])
    }

    @Test("a grant before the time is up cancels the troubleshooting")
    func grantBeforeTheTimeCancels() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)

        rig.board.set(.accessibility, to: .granted)
        rig.clock.advance(by: .seconds(10))
        await rig.monitor.refresh()
        let pendingAfterTheGrant = rig.clock.pendingSleeps
        rig.clock.advance(by: .seconds(60))
        await rig.settle()

        #expect(pendingAfterTheGrant == 0)
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("the troubleshooting goes away when the permission is granted at last")
    func staleEndsWithTheGrant() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }

        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.refresh()

        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("coming back to a permission that is granted by then starts no timer")
    func grantedOnReturn() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)

        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.appDidBecomeActive()
        await rig.settle()

        #expect(rig.clock.suspendedSleeps == 0)
        #expect(rig.monitor.followUps.isEmpty)
    }

    @Test("only the permission that stays denied gets the troubleshooting")
    func staleIsPerPermission() async {
        let rig = Rig([.microphone: .denied, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .microphone)
        rig.monitor.openSettings(for: .accessibility)

        rig.board.set(.accessibility, to: .granted)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.microphone] == .stale }

        #expect(rig.monitor.followUps == [.microphone: .stale])
    }

    @Test("a request that leaves the permission denied, as Accessibility does, is followed up the same way")
    func staleAfterARequest() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        await rig.monitor.request(.accessibility)

        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }

        #expect(rig.monitor.followUps == [.accessibility: .stale])
    }

    @Test("a prompt the user answered with Deny is not a trip to System Settings, so it gets no troubleshooting")
    func deniedPromptIsNotStale() async {
        let checker = AnsweringChecker([.microphone: .notDetermined], answering: .denied)
        let clock = ManualClock()
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: clock)
        await monitor.refresh()
        await monitor.request(.microphone)

        await monitor.appDidBecomeActive()
        for _ in 0..<20 { await Task.yield() }

        #expect(clock.suspendedSleeps == 0)
        #expect(monitor.followUps.isEmpty)
    }

    @Test("a prompt that is still up when the app becomes active starts no timer")
    func promptStillUpStartsNoTimer() async {
        let checker = FakePermissionsChecker([.microphone: .notDetermined], gatedRequests: true)
        let clock = ManualClock()
        let monitor = PermissionsMonitor(checker: checker, openSettings: { _ in }, clock: clock)
        let asking = Task { await monitor.request(.microphone) }
        await checker.requestEntered.wait()

        await monitor.appDidBecomeActive()
        for _ in 0..<20 { await Task.yield() }
        let sleepsWhileThePromptIsUp = clock.suspendedSleeps
        checker.releaseRequest()
        await asking.value

        #expect(sleepsWhileThePromptIsUp == 0)
    }

    @Test("coming back twice, or again after the troubleshooting shows, starts one timer at most")
    func oneTimerPerPermission() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)

        await rig.monitor.appDidBecomeActive()
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)
        await rig.settle()
        let whileCounting = rig.clock.pendingSleeps
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.followUps[.accessibility] == .stale }
        await rig.monitor.appDidBecomeActive()
        await rig.settle()

        #expect(whileCounting == 1)
        #expect(rig.clock.suspendedSleeps == 1)
    }

    @Test("a grant the monitor has not seen yet is read when the time is up, and is not stale")
    func grantUnseenAtTheEnd() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        await rig.monitor.refresh()
        rig.monitor.openSettings(for: .accessibility)
        await rig.monitor.appDidBecomeActive()
        await rig.clock.waitForSleeps(1)

        rig.board.set(.accessibility, to: .granted)
        rig.clock.advance(by: .seconds(30))
        await waitUntil { rig.monitor.statuses[.accessibility] == .granted }
        await rig.settle()

        #expect(rig.monitor.followUps.isEmpty)
        #expect(!rig.diagnostics.events.contains(.permissionGuidanceShown(permission: .accessibility)))
    }
}
