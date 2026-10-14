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

    @ObservationIgnored private let checker: any PermissionsChecker
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var poll: Task<Void, Never>?
    /// Numbers the reads in the order they began, so that a slow one cannot put older statuses over a newer read.
    @ObservationIgnored private var readsBegun = 0
    @ObservationIgnored private var newestReadApplied = 0

    /// - Parameters:
    ///   - clock: Times the poll. Tests pass a `ManualClock`.
    ///   - pollInterval: The pause between reads while the onboarding is visible.
    public init(
        checker: any PermissionsChecker,
        clock: any Clock<Duration> = ContinuousClock(),
        needs: PermissionNeeds = PermissionNeeds(),
        pollInterval: Duration = .seconds(1)
    ) {
        self.checker = checker
        self.clock = clock
        self.needs = needs
        self.pollInterval = pollInterval
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

    // MARK: Reading

    /// Reads the requested permissions now.
    public func refresh() async {
        readsBegun += 1
        let number = readsBegun
        var read: [Permission: PermissionStatus] = [:]
        for permission in requested { read[permission] = await checker.status(permission) }
        guard number > newestReadApplied else { return }
        newestReadApplied = number
        statuses = read
        hasReadStatuses = true
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

    /// Reads the statuses because the user came back to the app.
    public func appDidBecomeActive() async {
        await refresh()
    }

    /// Calls `appDidBecomeActive()` for each activation the app reports, until the stream ends.
    public func run(activations: AsyncStream<Void>) async {
        for await _ in activations { await appDidBecomeActive() }
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
