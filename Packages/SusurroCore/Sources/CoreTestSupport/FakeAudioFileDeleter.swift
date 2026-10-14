import Domain
import Foundation
import Synchronization

/// A deleter that keeps a list of the files it was asked to delete. Each URL can be made to fail, and then to work again.
public final class FakeAudioFileDeleter: AudioFileDeleting {
    public struct Failure: Error, Sendable, Equatable {
        public init() {}
    }

    private struct State {
        var attempts: [URL] = []
        var deleted: [URL] = []
        var failing: Set<URL> = []
    }

    private let state = Mutex(State())

    public init(failing: Set<URL> = []) {
        state.withLock { $0.failing = failing }
    }

    /// Every URL it was asked to delete, in order, the failed attempts included.
    public var attempts: [URL] { state.withLock { $0.attempts } }
    /// The URLs it deleted.
    public var deleted: [URL] { state.withLock { $0.deleted } }

    public func setFailing(_ urls: Set<URL>) {
        state.withLock { $0.failing = urls }
    }

    public func delete(_ url: URL) async throws {
        try state.withLock { state in
            state.attempts.append(url)
            if state.failing.contains(url) { throw Failure() }
            state.deleted.append(url)
        }
    }
}
