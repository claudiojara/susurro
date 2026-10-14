import Domain
import Observation

/// What the app knows about the system permissions, kept current without a relaunch: the onboarding, the menu and the
/// overlay read their state from it.
///
/// The statuses are read again when the app becomes active, and every `pollInterval` only while the onboarding is
/// visible, so a permission granted or revoked in System Settings shows within a second of the user looking at it.
/// Only the requested permissions are read (`PermissionPolicy.requested(for:)`), and only the required ones can disable
/// dictation or bring the onboarding back (`blocking`): a conditional permission that is missing leaves its own feature
/// inactive and nothing else.
///
/// It also follows what the user was asked to do (`followUps`). A permission the user was asked for with a prompt, or sent
/// to System Settings for, is followed until its status changes. If it has not changed `staleAfter` after the user came
/// back to the app, the follow-up is `stale`, because a toggle that is on but reads as not allowed is the sign of a
/// grant that went stale, and the permission's troubleshooting steps apply.
@MainActor
@Observable
public final class PermissionsMonitor {
    /// Where the monitor stands with a permission the user was asked to act on. A follow-up only moves forward, in this
    /// order, and ends when the permission's status changes.
    public enum FollowUp: Comparable, Sendable {
        /// The system's request is open and its prompt may be up. The answer comes by itself.
        case requesting
        /// The user was sent to System Settings, or the request returned and the status stayed as it was. The status is
        /// read until it changes.
        case sentToSettings
        /// The status has not changed `staleAfter` after the user came back to the app: the troubleshooting steps apply.
        case stale
    }

    private struct Step {
        /// The status the permission had when the user was asked. The follow-up ends when a read differs from it.
        let baseline: PermissionStatus
        var phase: FollowUp
    }

    /// The last status read of each permission. A permission that has not been read is missing.
    public private(set) var statuses: [Permission: PermissionStatus] = [:]
    /// Which of the optional permissions the setup uses.
    public private(set) var needs: PermissionNeeds
    /// Whether the statuses have been read at least once. Until then nothing is known, so the onboarding is not asked for.
    public private(set) var hasReadStatuses = false
    /// The permissions the user was asked to act on whose status has not changed since.
    private var steps: [Permission: Step] = [:]

    @ObservationIgnored private let checker: any PermissionsChecker
    @ObservationIgnored private let openSettingsAction: @MainActor (Permission) -> Void
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let staleAfter: Duration
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var staleTimers: [Permission: Task<Void, Never>] = [:]
    @ObservationIgnored private var requestsInFlight: Set<Permission> = []
    /// Numbers the reads in the order they began, so that a slow one cannot put older statuses over a newer read.
    @ObservationIgnored private var readsBegun = 0
    @ObservationIgnored private var newestReadApplied = 0

    /// - Parameters:
    ///   - openSettings: Opens the System Settings pane where the user changes a permission.
    ///   - clock: Times the poll and the stale-guidance wait. Tests pass a `ManualClock`.
    ///   - pollInterval: The pause between reads while the onboarding is visible.
    ///   - staleAfter: How long a permission may stay denied after the user came back from System Settings.
    public init(
        checker: any PermissionsChecker,
        openSettings: @escaping @MainActor (Permission) -> Void,
        clock: any Clock<Duration> = ContinuousClock(),
        needs: PermissionNeeds = PermissionNeeds(),
        pollInterval: Duration = .seconds(1),
        staleAfter: Duration = .seconds(30)
    ) {
        self.checker = checker
        openSettingsAction = openSettings
        self.clock = clock
        self.needs = needs
        self.pollInterval = pollInterval
        self.staleAfter = staleAfter
    }

    // MARK: What the permissions mean now

    /// What the setup asks the user for, the onboarding rows.
    public var requested: [Permission] { PermissionPolicy.requested(for: needs) }
    /// The required permissions that are not granted.
    public var blocking: [Permission] { PermissionPolicy.blocking(statuses: statuses) }
    public var isOnboardingComplete: Bool { PermissionPolicy.isOnboardingComplete(statuses: statuses) }
    /// Whether the onboarding must be shown: a required permission is missing, once the statuses are known.
    public var needsOnboarding: Bool { hasReadStatuses && !isOnboardingComplete }
    /// Why dictation is off, from `blocking` only, or nil when nothing blocks it.
    /// Nothing is said before the first read, as with `needsOnboarding`, because nothing is known yet.
    public var disabledReason: DictationDisabledReason? {
        hasReadStatuses ? DictationDisabledReason(blocking: blocking) : nil
    }
    /// Where the monitor stands with each permission the user was asked to act on and whose status has not changed since.
    public var followUps: [Permission: FollowUp] { steps.mapValues(\.phase) }

    // MARK: Reading

    /// Reads the requested permissions now.
    public func refresh() async {
        readsBegun += 1
        let number = readsBegun
        var read: [Permission: PermissionStatus] = [:]
        for permission in requested { read[permission] = await checker.status(permission) }
        guard number > newestReadApplied else { return }
        newestReadApplied = number
        apply(read)
    }

    /// Changes what the setup uses, and reads the statuses of the permissions it now asks for.
    public func setNeeds(_ needs: PermissionNeeds) async {
        guard needs != self.needs else { return }
        self.needs = needs
        for permission in steps.keys where !requested.contains(permission) { endFollowUp(of: permission) }
        await refresh()
    }

    /// Polls every `pollInterval` while the onboarding is visible, and not otherwise. The first read is at once.
    public func setOnboardingVisible(_ isVisible: Bool) {
        guard isVisible else {
            poll?.cancel()
            poll = nil
            return
        }
        guard poll == nil else { return }
        poll = Task { [weak self, clock, pollInterval] in
            // `self` is held only while a read runs, so a monitor that is let go also ends its poll.
            while !Task.isCancelled, self != nil {
                await self?.refresh()
                do { try await clock.sleep(for: pollInterval) } catch { return }
            }
        }
    }

    /// Reads the statuses because the user came back to the app, and starts the wait for the stale-grant guidance on
    /// each permission they were sent away for whose status has not changed, whatever it is. A prompt that is still up
    /// has not been answered, so it is not counted yet.
    public func appDidBecomeActive() async {
        await refresh()
        for (permission, step) in steps where step.phase == .sentToSettings && staleTimers[permission] == nil {
            startStaleTimer(for: permission)
        }
    }

    /// Calls `appDidBecomeActive()` for each activation the app reports, until the stream ends.
    public func run(activations: AsyncStream<Void>) async {
        for await _ in activations { await appDidBecomeActive() }
    }

    // MARK: Acting

    /// Asks the system for the permission, which may show its prompt, and follows it until its status changes. A
    /// permission that is granted, whose prompt is already up, or that the setup does not use is not asked for.
    public func request(_ permission: Permission) async {
        guard requested.contains(permission), statuses[permission] != .granted,
            requestsInFlight.insert(permission).inserted
        else { return }
        follow(permission, as: .requesting)
        await checker.request(permission)
        requestsInFlight.remove(permission)
        if steps[permission]?.phase == .requesting { steps[permission]?.phase = .sentToSettings }
        await refresh()
    }

    /// Opens the System Settings pane of the permission, and follows it until its status changes. A permission the setup
    /// does not use is left alone.
    public func openSettings(for permission: Permission) {
        guard requested.contains(permission) else { return }
        openSettingsAction(permission)
        follow(permission, as: .sentToSettings)
    }

    // MARK: Follow-up

    private func apply(_ read: [Permission: PermissionStatus]) {
        statuses = read
        hasReadStatuses = true
        for (permission, status) in read where steps[permission].map({ $0.baseline != status }) == true {
            endFollowUp(of: permission)
        }
    }

    /// Starts following a permission that is not granted, or moves its follow-up forward to `phase`.
    private func follow(_ permission: Permission, as phase: FollowUp) {
        let current = statuses[permission] ?? .notDetermined
        guard current != .granted else { return }
        // A follow-up that is on ends as soon as a read differs from its baseline, so the baseline is always the status now.
        steps[permission] = Step(baseline: current, phase: max(steps[permission]?.phase ?? phase, phase))
    }

    /// The status changed, or the setup stopped using the permission, so the follow-up is over. A permission's timer
    /// exists only while it is followed, so ending the follow-up ends the timer too.
    private func endFollowUp(of permission: Permission) {
        steps[permission] = nil
        staleTimers.removeValue(forKey: permission)?.cancel()
    }

    private func startStaleTimer(for permission: Permission) {
        staleTimers[permission] = Task { [weak self, clock, staleAfter] in
            do { try await clock.sleep(for: staleAfter) } catch { return }
            await self?.staleTimeElapsed(for: permission)
        }
    }

    /// The time is up: the status is read once more, and a follow-up that is still on, so the status is the one it was
    /// and is not granted, turns stale. The timer stays in the table until the follow-up ends, which keeps a second
    /// one from starting.
    private func staleTimeElapsed(for permission: Permission) async {
        await refresh()
        steps[permission]?.phase = .stale
    }
}
