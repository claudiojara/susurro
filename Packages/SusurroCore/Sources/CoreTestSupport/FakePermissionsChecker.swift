import Domain

/// Reports fixed statuses. A permission that is not listed is `notDetermined`. A `gated` checker suspends in
/// `status` until `releaseStatus()`, after signalling `entered`.
public struct FakePermissionsChecker: PermissionsChecker {
    public let entered = Gate()
    private let statuses: [Permission: PermissionStatus]
    private let release: Gate?

    public init(
        _ statuses: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted],
        gated: Bool = false
    ) {
        self.statuses = statuses
        release = gated ? Gate() : nil
    }

    public func releaseStatus() { release?.open() }

    public func status(_ permission: Permission) async -> PermissionStatus {
        entered.open()
        await release?.wait()
        return statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: Permission) async {}
}
