public enum Permission: Sendable, Hashable {
    case microphone
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionsChecker: Sendable {
    func status(_ permission: Permission) async -> PermissionStatus
}
