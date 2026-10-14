import Domain

/// Runs insertions one at a time, in the order they were submitted. A submission starts when the one before it has
/// returned, so two dictations never write to the pasteboard at once.
@MainActor
final class InsertionQueue {
    private var last: Task<Void, Never>?

    /// Waits for the submissions before this one, runs `work`, and returns its outcome. Cancelling the caller cancels
    /// `work`, whether it is waiting in line or running.
    func run(_ work: @escaping @MainActor () async -> InsertionOutcome) async -> InsertionOutcome {
        let previous = last
        let task = Task { @MainActor () -> InsertionOutcome in
            await previous?.value
            return await work()
        }
        last = Task { @MainActor in _ = await task.value }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
