import Domain
import Foundation
import Synchronization

/// A recording store that keeps the samples in memory. It logs what was written and deleted, and it can be told to fail
/// at each step the real store can fail at. The files it names do not exist.
public final class FakeRecordingStore: AudioRecordingStore {
    /// How the store misbehaves.
    public struct Faults: Sendable {
        /// `begin` throws.
        public var beginFails = false
        /// `append` throws on the call with this number (from 1) and on every later one.
        public var appendFailsFromCall: Int?
        /// `finish` throws this.
        public var finishError: RecordingStoreError?
        /// `finish` reports this many samples instead of the ones appended, as a damaged file would read back.
        public var reportedSampleCount: Int?
        /// `load` throws.
        public var loadFails = false

        public init(
            beginFails: Bool = false,
            appendFailsFromCall: Int? = nil,
            finishError: RecordingStoreError? = nil,
            reportedSampleCount: Int? = nil,
            loadFails: Bool = false
        ) {
            self.beginFails = beginFails
            self.appendFailsFromCall = appendFailsFromCall
            self.finishError = finishError
            self.reportedSampleCount = reportedSampleCount
            self.loadFails = loadFails
        }
    }

    private struct State {
        var begun: [SessionID] = []
        var samples: [SessionID: [Float]] = [:]
        var appendCalls: [Int] = []
        var finished: [SessionID] = []
        var aborted: [SessionID] = []
        var deleted: [URL] = []
        var watchers: [(total: Int, gate: Gate)] = []
    }

    private let state = Mutex(State())
    private let faults: Faults

    public init(_ faults: Faults = Faults()) {
        self.faults = faults
    }

    /// Where the recording of `id` would be.
    public static func url(for id: SessionID) -> URL {
        URL(filePath: "/fake-recordings/\(id).caf")
    }

    public var begun: [SessionID] { state.withLock { $0.begun } }
    public var finished: [SessionID] { state.withLock { $0.finished } }
    public var aborted: [SessionID] { state.withLock { $0.aborted } }
    public var deletedURLs: [URL] { state.withLock { $0.deleted } }
    /// The size in samples of each `append`, in order.
    public var appendSizes: [Int] { state.withLock { $0.appendCalls } }

    public func samples(of id: SessionID) -> [Float] { state.withLock { $0.samples[id] ?? [] } }

    /// Puts a recording in the store as if it had been written, for a test that starts at the stored audio.
    public func stored(_ clip: AudioClip, as id: SessionID = SessionID()) -> VerifiedRecording {
        state.withLock { $0.samples[id] = clip.samples }
        return VerifiedRecording(id: id, url: Self.url(for: id), sampleCount: clip.samples.count)
    }

    /// Suspends until at least `count` samples were appended in total, over every recording.
    public func waitForAppended(samples count: Int) async {
        let gate = state.withLock { state -> Gate? in
            if state.samples.values.reduce(0, { $0 + $1.count }) >= count { return nil }
            let gate = Gate()
            state.watchers.append((count, gate))
            return gate
        }
        await gate?.wait()
    }

    public func begin(_ id: SessionID) async throws -> any AudioRecordingSink {
        if faults.beginFails { throw RecordingStoreError.writeFailed("begin") }
        state.withLock { state in
            state.begun.append(id)
            state.samples[id] = []
        }
        return Sink(id: id, store: self)
    }

    public func load(_ recording: VerifiedRecording) async throws -> AudioClip {
        if faults.loadFails { throw RecordingStoreError.verificationFailed("load") }
        guard let samples = state.withLock({ $0.samples[recording.id] }) else { throw RecordingStoreError.missing }
        return AudioClip(samples: samples)
    }

    public func delete(_ url: URL) async throws {
        state.withLock { state in
            state.deleted.append(url)
            for id in state.samples.keys where Self.url(for: id) == url { state.samples[id] = nil }
        }
    }

    fileprivate func append(_ chunk: AudioChunk, to id: SessionID) throws {
        let (call, gates) = state.withLock { state -> (Int, [Gate]) in
            state.appendCalls.append(chunk.samples.count)
            let call = state.appendCalls.count
            if let failing = faults.appendFailsFromCall, call >= failing { return (call, []) }
            state.samples[id, default: []].append(contentsOf: chunk.samples)
            let total = state.samples.values.reduce(0) { $0 + $1.count }
            let ready = state.watchers.filter { $0.total <= total }
            state.watchers.removeAll { $0.total <= total }
            return (call, ready.map(\.gate))
        }
        if let failing = faults.appendFailsFromCall, call >= failing { throw RecordingStoreError.writeFailed("append") }
        for gate in gates { gate.open() }
    }

    fileprivate func finish(_ id: SessionID) throws -> VerifiedRecording {
        if let error = faults.finishError { throw error }
        let count = state.withLock { state -> Int in
            state.finished.append(id)
            return state.samples[id]?.count ?? 0
        }
        return VerifiedRecording(id: id, url: Self.url(for: id), sampleCount: faults.reportedSampleCount ?? count)
    }

    fileprivate func abort(_ id: SessionID) {
        state.withLock { state in
            state.aborted.append(id)
            state.samples[id] = nil
        }
    }

    private struct Sink: AudioRecordingSink {
        let id: SessionID
        let store: FakeRecordingStore

        func append(_ chunk: AudioChunk) async throws { try store.append(chunk, to: id) }
        func finish() async throws -> VerifiedRecording { try store.finish(id) }
        func abort() async { store.abort(id) }
    }
}
