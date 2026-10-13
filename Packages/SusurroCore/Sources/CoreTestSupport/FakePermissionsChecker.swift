import Domain
import Synchronization

/// Reports fixed statuses and logs every request. A permission that is not listed is `notDetermined`. A `gated`
/// checker suspends in `status` until `releaseStatus()`, after signalling `entered`. One with `gatedRequests` suspends
/// in `request` until `releaseRequest()`, after signalling `requestEntered`, as the system does while its prompt is up.
public struct FakePermissionsChecker: PermissionsChecker {
    private final class RequestLog: Sendable {
        private let items = Mutex<[Permission]>([])
        var all: [Permission] { items.withLock { $0 } }
        func append(_ permission: Permission) { items.withLock { $0.append(permission) } }
    }

    public let entered = Gate()
    public let requestEntered = Gate()
    private let statuses: [Permission: PermissionStatus]
    private let release: Gate?
    private let requestRelease: Gate?
    private let log = RequestLog()

    public init(
        _ statuses: [Permission: PermissionStatus] = [.microphone: .granted],
        gated: Bool = false,
        gatedRequests: Bool = false
    ) {
        self.statuses = statuses
        release = gated ? Gate() : nil
        requestRelease = gatedRequests ? Gate() : nil
    }

    /// The permissions that were requested, in order.
    public var requested: [Permission] { log.all }

    public func releaseStatus() { release?.open() }
    public func releaseRequest() { requestRelease?.open() }

    public func status(_ permission: Permission) async -> PermissionStatus {
        entered.open()
        await release?.wait()
        return statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: Permission) async {
        log.append(permission)
        requestEntered.open()
        await requestRelease?.wait()
    }
}
