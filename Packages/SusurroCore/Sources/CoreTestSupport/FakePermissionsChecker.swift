import Domain

/// Reports fixed statuses. A permission that is not listed is `notDetermined`.
public struct FakePermissionsChecker: PermissionsChecker {
    private let statuses: [Permission: PermissionStatus]

    public init(_ statuses: [Permission: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]) {
        self.statuses = statuses
    }

    public func status(_ permission: Permission) async -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: Permission) async {}
}
