/// One wall-clock budget for a whole insertion. Each wait has a limit of its own, and none of them may run past the end
/// of the budget: a pause that takes far longer than asked, such as when the main thread is busy, then shortens the
/// waits that come after it instead of pushing the insertion past the coordinator's limit.
struct InsertBudget {
    let end: Duration

    /// - Parameters:
    ///   - start: The time on the inserter's clock when the insertion began.
    ///   - length: How long the insertion may take in all.
    init(startingAt start: Duration, length: Duration = PasteTiming.insertBudget) {
        end = start + length
    }

    /// When a wait that may last `limit` from `now` has to end: its own limit, or the end of the budget if that is sooner.
    func deadline(for limit: Duration, from now: Duration) -> Duration {
        min(now + limit, end)
    }

    /// How much of the budget is left at `now`. Never negative.
    func remaining(at now: Duration) -> Duration {
        max(.zero, end - now)
    }
}
