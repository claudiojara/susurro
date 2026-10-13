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
}

public enum CaptureError: Error, Sendable, Equatable {
    case noInputDevice
}

public protocol AudioCaptureSource: Sendable {
    /// Starts capturing. The first chunk is the readiness signal: it arrives with the first real input buffer.
    func start() async throws -> AsyncThrowingStream<AudioChunk, Error>
    /// Stops capturing and finishes the stream after every captured chunk has been delivered.
    func stop() async
}
