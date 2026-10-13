import Domain
import Synchronization

/// A capture source for one recording: chunks emitted before `start` are buffered, and `stop` ends the stream.
/// With `tailAfterStop`, `stop` returns first and the stream delivers that last chunk shortly after, then ends.
public final class FakeAudioCaptureSource: AudioCaptureSource {
    private struct Counts {
        var starts = 0
        var stops = 0
    }

    private let stream: AsyncThrowingStream<AudioChunk, Error>
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private let startFailure: (any Error)?
    private let tailAfterStop: [Float]?
    private let counts = Mutex(Counts())

    public init(startFailure: (any Error)? = nil, tailAfterStop: [Float]? = nil) {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        self.startFailure = startFailure
        self.tailAfterStop = tailAfterStop
    }

    public var startCount: Int { counts.withLock { $0.starts } }
    public var stopCount: Int { counts.withLock { $0.stops } }

    public func emit(_ chunk: AudioChunk) { continuation.yield(chunk) }

    /// Ends the stream with an error, as a device that disappears mid-recording would.
    public func fail(_ error: any Error) { continuation.finish(throwing: error) }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        counts.withLock { $0.starts += 1 }
        if let startFailure { throw startFailure }
        return stream
    }

    public func stop() async {
        counts.withLock { $0.stops += 1 }
        guard let tailAfterStop else { return continuation.finish() }
        Task { [continuation] in
            try? await Task.sleep(for: .milliseconds(50))
            continuation.yield(AudioChunk(samples: tailAfterStop))
            continuation.finish()
        }
    }
}
