import CoreTestSupport
import Domain
import Synchronization

@testable import Presentation

/// The System Settings panes the monitor was asked to open.
@MainActor
final class Panes {
    var opened: [Permission] = []
}

/// A monitor over a permissions board the test changes as the user does in System Settings, and a clock it advances.
@MainActor
struct Rig {
    let board: MutablePermissionsChecker
    let clock = ManualClock()
    let panes = Panes()
    let monitor: PermissionsMonitor

    init(_ statuses: [Permission: PermissionStatus], needs: PermissionNeeds = PermissionNeeds()) {
        let board = MutablePermissionsChecker(statuses)
        let clock = clock
        let panes = panes
        self.board = board
        monitor = PermissionsMonitor(
            checker: board, openSettings: { panes.opened.append($0) }, clock: clock, needs: needs)
    }

    /// Lets work that was started and is not waiting on the clock run to its end.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

/// Yields until `condition` holds. A test that is cancelled by its time limit stops waiting, so a bug fails the test
/// where a bare `while` loop would spin for good.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    while !condition(), !Task.isCancelled { await Task.yield() }
}

/// Answers a request the way the system does once the user has chosen: the status changes while the request is open.
final class AnsweringChecker: PermissionsChecker {
    private let statuses: Mutex<[Permission: PermissionStatus]>
    private let answer: PermissionStatus

    init(_ statuses: [Permission: PermissionStatus], answering answer: PermissionStatus) {
        self.statuses = Mutex(statuses)
        self.answer = answer
    }

    func status(_ permission: Permission) async -> PermissionStatus {
        statuses.withLock { $0[permission] ?? .notDetermined }
    }

    func request(_ permission: Permission) async {
        statuses.withLock { $0[permission] = answer }
    }
}
