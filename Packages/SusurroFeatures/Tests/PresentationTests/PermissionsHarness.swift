import CoreTestSupport
import Domain

@testable import Presentation

/// A monitor over a permissions board the test changes as the user does in System Settings, and a clock it advances.
@MainActor
struct Rig {
    let board: MutablePermissionsChecker
    let clock = ManualClock()
    let monitor: PermissionsMonitor

    init(_ statuses: [Permission: PermissionStatus], needs: PermissionNeeds = PermissionNeeds()) {
        let board = MutablePermissionsChecker(statuses)
        self.board = board
        monitor = PermissionsMonitor(checker: board, clock: clock, needs: needs)
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
