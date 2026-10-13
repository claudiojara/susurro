public enum Permission: Sendable, Hashable {
    case microphone
    case accessibility
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionsChecker: Sendable {
    func status(_ permission: Permission) async -> PermissionStatus
    /// Asks the system for the permission, which may show its prompt. A permission that is already decided is not
    /// asked again; the user changes it in System Settings.
    func request(_ permission: Permission) async
}
