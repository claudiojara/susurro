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
        let monitor = PermissionsMonitor(checker: checker, clock: ManualClock())
        let slow = Task { await monitor.refresh() }
        await checker.firstReadEntered.wait()

        await monitor.refresh()
        checker.releaseFirstRead.open()
        await slow.value

        #expect(monitor.statuses == [.microphone: .granted, .accessibility: .granted])
    }

    // MARK: Polling

    @Test("while the onboarding is visible the statuses are read at once and then every second")
    func pollsEverySecondWhileVisible() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])

        rig.monitor.setOnboardingVisible(true)
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

    @Test("nothing is read on a timer while the onboarding is hidden")
    func silentWhileHidden() async {
        let rig = Rig([.microphone: .granted])

        rig.clock.advance(by: .seconds(30))
        await rig.settle()

        #expect(rig.board.statusReads == 0)
        #expect(rig.clock.suspendedSleeps == 0)
    }

    @Test("hiding the onboarding stops the poll, and showing it again starts it again")
    func pollFollowsTheVisibility() async {
        let rig = Rig([.microphone: .granted])
        rig.monitor.setOnboardingVisible(true)
        await rig.clock.waitForSleeps(1)

        rig.monitor.setOnboardingVisible(false)
        let pendingWhenHidden = rig.clock.pendingSleeps
        rig.clock.advance(by: .seconds(10))
        await rig.settle()
        let readsWhenHidden = rig.board.statusReads
        rig.monitor.setOnboardingVisible(true)
        await rig.clock.waitForSleeps(2)

        #expect(pendingWhenHidden == 0)
        #expect(readsWhenHidden == 2)
        #expect(rig.board.statusReads == 4)
        #expect(rig.clock.pendingSleeps == 1)
    }

    @Test("showing the onboarding twice does not start a second poll")
    func onePollAtATime() async {
        let rig = Rig([.microphone: .granted])

        rig.monitor.setOnboardingVisible(true)
        rig.monitor.setOnboardingVisible(true)
        await rig.clock.waitForSleeps(1)
        await rig.settle()

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

    @Test("each activation the app reports is a read, until the stream ends")
    func activationStream() async {
        let rig = Rig([.microphone: .granted, .accessibility: .denied])
        let (activations, continuation) = AsyncStream.makeStream(of: Void.self)
        let running = Task { await rig.monitor.run(activations: activations) }

        continuation.yield()
        await waitUntil { rig.monitor.statuses[.accessibility] == .denied }
        rig.board.set(.accessibility, to: .granted)
        continuation.yield()
        await waitUntil { rig.monitor.statuses[.accessibility] == .granted }
        continuation.finish()
        await running.value

        #expect(rig.board.statusReads == 4)
    }

    // MARK: Revocation and the disabled reason

    @Test("a permission revoked while the app runs is published as denied and disables dictation with a reason")
    func revocation() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        await rig.monitor.refresh()
        let before = (rig.monitor.disabledReason, rig.monitor.needsOnboarding)

        rig.board.set(.accessibility, to: .denied)
        await rig.monitor.appDidBecomeActive()

        #expect(before.0 == nil)
        #expect(before.1 == false)
        #expect(rig.monitor.statuses[.accessibility] == .denied)
        #expect(rig.monitor.blocking == [.accessibility])
        #expect(rig.monitor.disabledReason?.permissions == [.accessibility])
        #expect(rig.monitor.needsOnboarding)
    }

    @Test("a revocation found by the poll shows within the second")
    func revocationFoundByThePoll() async {
        let rig = Rig([.microphone: .granted, .accessibility: .granted])
        rig.monitor.setOnboardingVisible(true)
        await rig.clock.waitForSleeps(1)

        rig.board.set(.microphone, to: .denied)
        rig.clock.advance(by: .seconds(1))
        await rig.clock.waitForSleeps(2)

        #expect(rig.monitor.disabledReason?.permissions == [.microphone])
    }

    @Test(
        "the reason names every missing required permission, in the order of the onboarding",
        arguments: [
            (
                [Permission.microphone: PermissionStatus.denied, .accessibility: .denied],
                [Permission.microphone, .accessibility],
                "Dictation is off until Microphone and Accessibility are allowed."
            ),
            (
                [.microphone: .granted, .accessibility: .notDetermined], [.accessibility],
                "Dictation is off until Accessibility is allowed."
            ),
            (
                [.microphone: .notDetermined, .accessibility: .granted], [.microphone],
                "Dictation is off until Microphone is allowed."
            ),
        ]
    )
    func reasonNamesTheMissingOnes(
        statuses: [Permission: PermissionStatus], expected: [Permission], message: String
    ) async {
        let rig = Rig(statuses)

        await rig.monitor.refresh()

        #expect(rig.monitor.disabledReason?.permissions == expected)
        #expect(rig.monitor.disabledReason?.message == message)
        #expect(rig.monitor.blocking == expected)
    }

    @Test("a denied or unread conditional permission neither disables dictation nor brings the onboarding back")
    func conditionalPermissionNeverGates() async {
        for status in [PermissionStatus.denied, .notDetermined] {
            let rig = Rig(
                [.microphone: .granted, .accessibility: .granted, .inputMonitoring: status, .screenRecording: status],
                needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))

            await rig.monitor.refresh()

            #expect(rig.monitor.statuses[.screenRecording] == status)
            #expect(rig.monitor.disabledReason == nil)
            #expect(rig.monitor.blocking.isEmpty)
            #expect(rig.monitor.isOnboardingComplete)
            #expect(!rig.monitor.needsOnboarding)
        }
    }

    @Test("a missing required permission is the reason even when the conditional ones are missing too")
    func reasonIgnoresConditionalPermissions() async {
        let rig = Rig(
            [.microphone: .denied, .accessibility: .granted, .inputMonitoring: .denied, .screenRecording: .denied],
            needs: PermissionNeeds(modifierOnlyHotkey: true, ocrEnabled: true))

        await rig.monitor.refresh()

        #expect(rig.monitor.disabledReason?.permissions == [.microphone])
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
            checker: MutablePermissionsChecker([.microphone: .granted]), clock: clock)
        monitor?.setOnboardingVisible(true)
        await clock.waitForSleeps(1)

        monitor = nil
        clock.advance(by: .seconds(1))
        for _ in 0..<20 { await Task.yield() }

        #expect(clock.pendingSleeps == 0)
        #expect(clock.suspendedSleeps == 1)
    }
}
