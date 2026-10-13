import Domain
import Synchronization

/// A capture source for one recording: chunks emitted before `start` are buffered, and `stop` ends the stream.
/// With `tailAfterStop`, `stop` returns first and the stream delivers that last chunk shortly after, then ends.
public final class FakeAudioCaptureSource: AudioCaptureSource {
    private let stream: AsyncThrowingStream<AudioChunk, Error>
    private let continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
    private let startFailure: (any Error)?
    private let tailAfterStop: [Float]?
    private let starts = Mutex(0)
    private let stops = Mutex(0)

    public init(startFailure: (any Error)? = nil, tailAfterStop: [Float]? = nil) {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        self.startFailure = startFailure
        self.tailAfterStop = tailAfterStop
    }

    public var startCount: Int { starts.withLock { $0 } }
    public var stopCount: Int { stops.withLock { $0 } }

    public func emit(_ chunk: AudioChunk) { continuation.yield(chunk) }

    /// Ends the stream with an error, as a device that disappears mid-recording would.
    public func fail(_ error: any Error) { continuation.finish(throwing: error) }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        starts.withLock { $0 += 1 }
        if let startFailure { throw startFailure }
        return stream
    }

    public func stop() async {
        stops.withLock { $0 += 1 }
        guard let tailAfterStop else { return continuation.finish() }
        Task { [continuation] in
            try? await Task.sleep(for: .milliseconds(50))
            continuation.yield(AudioChunk(samples: tailAfterStop))
            continuation.finish()
        }
    }
}
