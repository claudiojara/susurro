import Domain
import Synchronization

/// A capture source whose every `start` returns a fresh stream. Chunks emitted while no capture is running are
/// buffered for the next one.
public final class FakeAudioCaptureSource: AudioCaptureSource {
    /// What `stop` does: end the stream, return while leaving it open (until `finish()`), or never return.
    public enum OnStop: Sendable {
        case finishStream
        case holdStreamOpen
        case hang
    }

    private struct State {
        var starts = 0
        var stops = 0
        var pending = AsyncThrowingStream<AudioChunk, Error>.makeStream()
        var active: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    }

    /// Opened when `stop` returns, in `holdStreamOpen` mode.
    public let stopped = Gate()
    private let state = Mutex(State())
    private let startFailure: (any Error)?
    private let startGate: Gate?
    private let onStop: OnStop

    /// A capture that `gatesStart` suspends in `start` until `releaseStart()`, and only then fails or starts.
    public init(startFailure: (any Error)? = nil, gatesStart: Bool = false, onStop: OnStop = .finishStream) {
        self.startFailure = startFailure
        startGate = gatesStart ? Gate() : nil
        self.onStop = onStop
    }

    public var startCount: Int { state.withLock { $0.starts } }
    public var stopCount: Int { state.withLock { $0.stops } }

    public func emit(_ chunk: AudioChunk) {
        _ = state.withLock { ($0.active ?? $0.pending.continuation).yield(chunk) }
    }

    /// Ends the running capture's stream.
    public func finish() { endActive(with: nil) }

    /// Ends the running capture's stream with an error, as a device that disappears mid-recording would.
    public func fail(_ error: any Error) { endActive(with: error) }

    public func releaseStart() { startGate?.open() }

    public func start() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        state.withLock { $0.starts += 1 }
        await startGate?.wait()
        if let startFailure { throw startFailure }
        return state.withLock { state in
            let session = state.pending
            state.pending = AsyncThrowingStream.makeStream()
            state.active = session.continuation
            return session.stream
        }
    }

    public func stop() async {
        state.withLock { $0.stops += 1 }
        switch onStop {
        case .finishStream: finish()
        case .holdStreamOpen: stopped.open()
        case .hang: await Gate().wait()
        }
    }

    private func endActive(with error: (any Error)?) {
        let active = state.withLock { state in
            defer { state.active = nil }
            return state.active
        }
        active?.finish(throwing: error)
    }
}
