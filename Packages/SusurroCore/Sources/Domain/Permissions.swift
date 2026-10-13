public enum Permission: Sendable, Hashable, CaseIterable {
    case microphone
    case accessibility
    case inputMonitoring
    case screenRecording
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionsChecker: Sendable {
    func status(_ permission: Permission) async -> PermissionStatus
    func request(_ permission: Permission) async
}
