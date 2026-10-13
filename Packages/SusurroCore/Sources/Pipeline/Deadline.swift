import Domain

/// Runs `operation`, giving up with `PipelineError.timedOut(stage)` once `sleep(limit)` returns. The loser of the race
/// is cancelled and abandoned, so an operation that ignores cancellation cannot block the caller. Throws
/// `CancellationError` when the calling task is cancelled.
func withDeadline<T: Sendable>(
    _ limit: Duration,
    stage: PipelineError.Stage,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withDeadline(limit, stageAtExpiry: { stage }, sleep: sleep, operation: operation)
}

/// Like the deadline above, for a limit that covers several stages in turn: the error names the stage that
/// `stageAtExpiry` reports at the moment the limit runs out.
func withDeadline<T: Sendable>(
    _ limit: Duration,
    stageAtExpiry: @escaping @Sendable () async -> PipelineError.Stage,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    let (outcomes, results) = AsyncStream.makeStream(of: Result<T, any Error>.self)
    let work = Task {
        do { results.yield(.success(try await operation())) } catch { results.yield(.failure(error)) }
    }
    let timer = Task {
        guard (try? await sleep(limit)) != nil else { return }
        results.yield(.failure(PipelineError.timedOut(await stageAtExpiry())))
    }
    defer {
        work.cancel()
        timer.cancel()
    }
    var iterator = outcomes.makeAsyncIterator()
    guard let first = await iterator.next() else { throw CancellationError() }
    return try first.get()
}
