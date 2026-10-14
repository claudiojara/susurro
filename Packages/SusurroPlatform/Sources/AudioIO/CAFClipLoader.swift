import AVFoundation
import Domain
import Foundation

/// Reads a stored recording back as a clip. The recordings are Int16 CAF files at 16 kHz mono, which is what the
/// recognizer takes, so reading only converts the samples to Float32.
public struct CAFClipLoader: AudioClipLoading {
    public enum LoadError: Error, Sendable, Equatable {
        /// The file is not 16 kHz mono, so it is not one of the app's recordings.
        case unsupportedFormat
        case empty
    }

    public init() {}

    public func clip(at url: URL) async throws -> AudioClip {
        // Reading a long recording takes a moment, so it does not run on the caller's executor.
        try await Task.detached(priority: .utility) { try Self.read(url) }.value
    }

    private static func read(_ url: URL) throws -> AudioClip {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard Int(format.sampleRate) == AudioClip.sampleRate, format.channelCount == 1 else {
            throw LoadError.unsupportedFormat
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { throw LoadError.empty }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw LoadError.unsupportedFormat
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { throw LoadError.empty }
        return AudioClip(samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    }
}
