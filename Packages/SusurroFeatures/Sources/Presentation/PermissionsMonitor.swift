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
/// It also follows what the user was asked to do. A permission the user was sent to System Settings for, or asked for
/// with a prompt that left it unchanged, is `waiting` until its status changes. If it is still denied `staleAfter` after
/// the user came back to the app, `staleGuidance` holds it, because a toggle that is on but reads denied is the sign of
/// a grant that went stale, which removing the app from the list and adding it again fixes.
@MainActor
@Observable
public final class PermissionsMonitor {
    /// Why dictation is off: the required permissions that are not granted.
    public struct DisabledReason: Equatable, Sendable {
        /// The missing required permissions, in the order of the onboarding. Never empty.
        public let permissions: [Permission]

        init?(blocking permissions: [Permission]) {
            guard !permissions.isEmpty else { return nil }
            self.permissions = permissions
        }

        public var message: String {
            let names = permissions.map(\.displayName).joined(separator: " and ")
            return "Dictation is off until \(names) \(permissions.count == 1 ? "is" : "are") allowed."
        }
    }

    /// The last status read of each permission. A permission that has not been read is missing.
    public private(set) var statuses: [Permission: PermissionStatus] = [:]
    /// Which of the optional permissions the setup uses.
    public private(set) var needs: PermissionNeeds
    /// Whether the statuses have been read at least once. Until then nothing is known, so the onboarding is not asked for.
    public private(set) var hasReadStatuses = false
    /// The permissions the user was asked to act on whose status has not changed since, each with the status it had.
    private var waitingFrom: [Permission: PermissionStatus] = [:]
    /// The permissions still denied `staleAfter` after the user came back from System Settings.
    public private(set) var staleGuidance: Set<Permission> = []

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
    public var disabledReason: DisabledReason? { DisabledReason(blocking: blocking) }
    /// The permissions the user was asked to act on whose status has not changed since.
    public var waiting: Set<Permission> { Set(waitingFrom.keys) }

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
    /// each permission they were sent away for that is still denied.
    public func appDidBecomeActive() async {
        await refresh()
        // A timer that has run stays in the table until the follow-up ends, so it is not started again.
        for permission in waitingFrom.keys where statuses[permission] == .denied && staleTimers[permission] == nil {
            startStaleTimer(for: permission)
        }
    }

    /// Calls `appDidBecomeActive()` for each activation the app reports, until the stream ends.
    public func run(activations: AsyncStream<Void>) async {
        for await _ in activations { await appDidBecomeActive() }
    }

    // MARK: Acting

    /// Asks the system for the permission, which may show its prompt, and shows it as waiting until its status changes.
    /// A permission that is granted, or whose prompt is already up, is not asked for.
    public func request(_ permission: Permission) async {
        guard statuses[permission] != .granted, requestsInFlight.insert(permission).inserted else { return }
        startWaiting(for: permission)
        await checker.request(permission)
        requestsInFlight.remove(permission)
        await refresh()
    }

    /// Opens the System Settings pane of the permission, and shows it as waiting until its status changes.
    public func openSettings(for permission: Permission) {
        openSettingsAction(permission)
        startWaiting(for: permission)
    }

    // MARK: Follow-up

    private func apply(_ read: [Permission: PermissionStatus]) {
        statuses = read
        hasReadStatuses = true
        for (permission, status) in read {
            if let baseline = waitingFrom[permission], baseline != status { endFollowUp(of: permission) }
        }
    }

    private func startWaiting(for permission: Permission) {
        let current = statuses[permission] ?? .notDetermined
        guard current != .granted else { return }
        waitingFrom[permission] = current
    }

    /// The status changed, so the user's step did its work. A permission's timer and its stale guidance exist only while
    /// it is waiting, so ending the wait ends them too.
    private func endFollowUp(of permission: Permission) {
        waitingFrom[permission] = nil
        staleGuidance.remove(permission)
        staleTimers.removeValue(forKey: permission)?.cancel()
    }

    private func startStaleTimer(for permission: Permission) {
        staleTimers[permission] = Task { [weak self, clock, staleAfter] in
            do { try await clock.sleep(for: staleAfter) } catch { return }
            await self?.staleTimeElapsed(for: permission)
        }
    }

    private func staleTimeElapsed(for permission: Permission) async {
        await refresh()
        if statuses[permission] == .denied { staleGuidance.insert(permission) }
    }
}

extension Permission {
    /// The name the user knows the permission by, as System Settings shows it.
    var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .screenRecording: "Screen Recording"
        }
    }
}
