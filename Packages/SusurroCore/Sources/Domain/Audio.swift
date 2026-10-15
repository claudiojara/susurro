import Foundation

/// A buffer of captured audio: 16 kHz mono Float32.
public struct AudioChunk: Sendable, Equatable {
    public let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }
}

/// A complete recording: 16 kHz mono Float32.
public struct AudioClip: Sendable, Equatable {
    public static let sampleRate = 16_000

    public let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    public var duration: Duration { Self.duration(ofSamples: samples.count) }

    /// How long `count` samples last.
    public static func duration(ofSamples count: Int) -> Duration {
        .nanoseconds(Int64(count) * 1_000_000_000 / Int64(sampleRate))
    }

    /// The index of the sample at `time`, rounded down. A negative time gives 0.
    public static func sampleIndex(at time: Duration) -> Int {
        let parts = time.components
        guard parts.seconds >= 0 else { return 0 }
        let nanoseconds = parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
        return Int(nanoseconds * Int64(sampleRate) / 1_000_000_000)
    }
}

public enum CaptureError: Error, Sendable, Equatable {
    case noInputDevice
    /// The input device went away while recording, and the capture could not get an input back. What was captured
    /// before is intact.
    case deviceRemoved
}

public protocol AudioCaptureSource: Sendable {
    /// Starts capturing. The first chunk is the readiness signal: it arrives with the first real input buffer.
    func start() async throws -> AsyncThrowingStream<AudioChunk, Error>
    /// Stops capturing and finishes the stream after every captured chunk has been delivered.
    func stop() async
}

/// Names one dictation attempt from the first key press to the last stage, and the audio file it owns.
public struct SessionID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

/// A recording that has been written out and read back: the file exists, can be read, holds samples, and lasts as long
/// as the samples written say.
public struct VerifiedRecording: Sendable, Equatable {
    public let id: SessionID
    public let url: URL
    public let sampleCount: Int

    public init(id: SessionID, url: URL, sampleCount: Int) {
        self.id = id
        self.url = url
        self.sampleCount = sampleCount
    }

    public var duration: Duration { AudioClip.duration(ofSamples: sampleCount) }
}

/// Why a recording could not be written or verified.
public enum RecordingStoreError: Error, Sendable, Equatable {
    /// The file could not be created or written.
    case writeFailed(String)
    /// The file was written but did not read back as the recording: unreadable, empty, or of the wrong length.
    case verificationFailed(String)
    /// The recording is not there to be read.
    case missing
}

/// Where a recording is written while it is captured. Recognition starts only from what `finish()` returns.
public protocol AudioRecordingSink: Sendable {
    /// Writes the chunk after everything appended before it.
    func append(_ chunk: AudioChunk) async throws
    /// Closes the file, reads it back, and checks it: readable, not empty, and as long as the samples written.
    func finish() async throws -> VerifiedRecording
    /// Closes the file and deletes it, as after a failure or a recording that is not kept.
    func abort() async
}

/// The durable home of recordings, one file per `SessionID`.
public protocol AudioRecordingStore: Sendable {
    /// Opens the file that the recording of `id` is written to.
    func begin(_ id: SessionID) async throws -> any AudioRecordingSink
    /// Reads a verified recording back whole, for the stages that work on the persisted audio.
    func load(_ recording: VerifiedRecording) async throws -> AudioClip
    /// Deletes the file at `url`. A file that is not there is not an error.
    func delete(_ url: URL) async throws
}
