import Domain
import Synchronization

/// A permissions checker whose statuses the test changes while it runs, as the user does in System Settings. It counts
/// the status reads and logs every request.
public final class MutablePermissionsChecker: PermissionsChecker {
    private struct State {
        var statuses: [Permission: PermissionStatus]
        var reads = 0
        var requests: [Permission] = []
    }

    private let state: Mutex<State>

    /// A permission that is not listed is `notDetermined`.
    public init(_ statuses: [Permission: PermissionStatus] = [:]) {
        state = Mutex(State(statuses: statuses))
    }

    public var statusReads: Int { state.withLock { $0.reads } }
    public var requested: [Permission] { state.withLock { $0.requests } }

    public func set(_ permission: Permission, to status: PermissionStatus) {
        state.withLock { $0.statuses[permission] = status }
    }

    public func status(_ permission: Permission) async -> PermissionStatus {
        state.withLock { state in
            state.reads += 1
            return state.statuses[permission] ?? .notDetermined
        }
    }

    public func request(_ permission: Permission) async {
        state.withLock { $0.requests.append(permission) }
    }
}
