import AVFoundation
import Domain
import Foundation
import Synchronization

/// Keeps each recording as an Int16 CAF file, one per dictation, named `<id>.caf` in one folder. The file is written as
/// the audio is captured, and a recording is handed out only after it has been read back.
///
/// CAF suits this: its header does not depend on the length of the data, so a file that a crash cut short still opens
/// with what was written until then.
public final class CAFRecordingStore: AudioRecordingStore {
    /// How far the length read back may differ from the samples written, in samples (10 ms).
    static let lengthTolerance: AVAudioFramePosition = 160
    /// The block read from each end of a file to check that it can be read.
    private static let probeFrames: AVAudioFrameCount = 1_024

    private let directory: @Sendable () -> URL
    private let diagnostics: any DiagnosticsLog

    /// - Parameters:
    ///   - directory: The folder the recordings live in, asked for each time. The app passes `Audio` in its folder of
    ///     Application Support. The store creates it when it is missing.
    ///   - diagnostics: Where each recording that was written and read back is reported, by id and length.
    public init(directory: @escaping @Sendable () -> URL, diagnostics: any DiagnosticsLog = NoDiagnostics()) {
        self.directory = directory
        self.diagnostics = diagnostics
    }

    public func begin(_ id: SessionID) async throws -> any AudioRecordingSink {
        let folder = directory()
        let url = folder.appending(path: "\(id).caf")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try CAFRecordingSink(id: id, url: url, diagnostics: diagnostics)
        } catch {
            throw RecordingStoreError.writeFailed(String(describing: error))
        }
    }

    public func load(_ recording: VerifiedRecording) async throws -> AudioClip {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: recording.url)
        } catch {
            throw RecordingStoreError.missing
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw RecordingStoreError.verificationFailed("empty")
        }
        do {
            try file.read(into: buffer)
        } catch {
            throw RecordingStoreError.verificationFailed(String(describing: error))
        }
        guard let channel = buffer.floatChannelData?[0] else { throw RecordingStoreError.verificationFailed("format") }
        return AudioClip(samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    }

    public func delete(_ url: URL) async throws {
        // Only the store's own files: a path from elsewhere is not the store's to delete.
        guard url.standardizedFileURL.deletingLastPathComponent().path == directory().standardizedFileURL.path else {
            throw RecordingStoreError.writeFailed("not a file of the recordings folder")
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw RecordingStoreError.writeFailed(String(describing: error))
        }
    }

    /// Reads the file back and checks it: it opens, it is 16 kHz mono, it holds about `expectedSamples` samples, and
    /// both ends of it can be read.
    static func verify(_ url: URL, expectedSamples: Int) throws {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw RecordingStoreError.verificationFailed("unreadable")
        }
        guard file.length > 0 else { throw RecordingStoreError.verificationFailed("empty") }
        guard file.fileFormat.sampleRate == Double(AudioClip.sampleRate), file.fileFormat.channelCount == 1 else {
            throw RecordingStoreError.verificationFailed("format")
        }
        guard abs(file.length - AVAudioFramePosition(expectedSamples)) <= lengthTolerance else {
            throw RecordingStoreError.verificationFailed("length")
        }
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: probeFrames)
        else { throw RecordingStoreError.verificationFailed("format") }
        do {
            for position in [0, max(0, file.length - AVAudioFramePosition(probeFrames))] {
                file.framePosition = position
                try file.read(into: buffer)
            }
        } catch {
            throw RecordingStoreError.verificationFailed("unreadable")
        }
    }
}

/// Writes one recording. `AVAudioFile` is not `Sendable`, so a lock serializes the calls and keeps the sink `Sendable`
/// without an unchecked escape hatch.
private final class CAFRecordingSink: AudioRecordingSink {
    private struct State {
        var file: AVAudioFile?
        var written = 0
    }

    private let id: SessionID
    private let url: URL
    private let format: AVAudioFormat
    private let diagnostics: any DiagnosticsLog
    private let state: Mutex<State>

    init(id: SessionID, url: URL, diagnostics: any DiagnosticsLog) throws {
        // Int16 on disk, Float32 in the buffers the file takes: the file converts as it writes.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(AudioClip.sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.id = id
        self.url = url
        self.diagnostics = diagnostics
        format = file.processingFormat
        state = Mutex(State(file: file))
    }

    func append(_ chunk: AudioChunk) async throws {
        guard !chunk.samples.isEmpty else { return }
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { throw RecordingStoreError.writeFailed("buffer") }
        chunk.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        try state.withLock { state in
            guard let file = state.file else { throw RecordingStoreError.writeFailed("closed") }
            do {
                try file.write(from: buffer)
            } catch {
                throw RecordingStoreError.writeFailed(String(describing: error))
            }
            state.written += chunk.samples.count
        }
    }

    func finish() async throws -> VerifiedRecording {
        // Releasing the file closes it, which is when the header is final.
        let written = state.withLock { state in
            state.file = nil
            return state.written
        }
        try CAFRecordingStore.verify(url, expectedSamples: written)
        let recording = VerifiedRecording(id: id, url: url, sampleCount: written)
        diagnostics.record(
            .recordingVerified(id: id.description, milliseconds: Int(recording.duration / .milliseconds(1))))
        return recording
    }

    func abort() async {
        state.withLock { $0.file = nil }
        try? FileManager.default.removeItem(at: url)
    }
}
