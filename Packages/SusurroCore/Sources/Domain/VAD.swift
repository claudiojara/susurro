/// A stretch of a recording in which someone speaks, measured from the start of the recording.
public struct SpeechSegment: Sendable, Equatable {
    public let start: Duration
    public let end: Duration

    public init(start: Duration, end: Duration) {
        self.start = start
        self.end = end
    }
}

/// What a voice activity detector found in a recording: the segments with speech, in time order. None means that no one
/// spoke.
public struct VADResult: Sendable, Equatable {
    public let segments: [SpeechSegment]

    public init(segments: [SpeechSegment]) {
        self.segments = segments
    }

    public var hasSpeech: Bool { !segments.isEmpty }
}

/// Finds the speech in a recording. It reads the clip and never changes it.
public protocol VoiceActivityDetector: Sendable {
    func analyze(_ clip: AudioClip) async throws -> VADResult
}
