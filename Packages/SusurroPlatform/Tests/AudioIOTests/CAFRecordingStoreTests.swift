import AVFoundation
import CoreTestSupport
import Domain
import Foundation
import Testing

@testable import AudioIO

@Suite("CAF recording store", .timeLimit(.minutes(1)))
struct CAFRecordingStoreTests {
    private struct Rig {
        let folder: URL
        let store: CAFRecordingStore

        init() {
            folder = FileManager.default.temporaryDirectory.appending(
                path: "susurro-caf-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            store = CAFRecordingStore(directory: { [folder] in folder })
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static func tone(seconds: Double, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * Double(AudioClip.sampleRate))
        return (0..<count).map { amplitude * sin(Float($0) * 0.05) }
    }

    @Test("an Int16 CAF is written incrementally, and the file on disk grows before the recording is finished")
    func writesIncrementally() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let id = SessionID()
        let sink = try await rig.store.begin(id)
        let url = rig.folder.appending(path: "\(id).caf")

        try await sink.append(AudioChunk(samples: Self.tone(seconds: 1)))
        let afterFirst = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        try await sink.append(AudioChunk(samples: Self.tone(seconds: 1)))
        let afterSecond = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0

        #expect(afterFirst > 0)
        #expect(afterSecond > afterFirst)
        let recording = try await sink.finish()
        #expect(recording.id == id)
        #expect(recording.url == url)
        #expect(recording.sampleCount == 2 * AudioClip.sampleRate)
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(url.pathExtension == "caf")
    }

    @Test("a verified recording is logged by id and length, and never by path or content")
    func logsTheVerifiedRecording() async throws {
        let log = RecordingDiagnostics()
        let folder = FileManager.default.temporaryDirectory.appending(path: "susurro-caf-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CAFRecordingStore(directory: { folder }, diagnostics: log)
        let id = SessionID()
        let sink = try await store.begin(id)
        try await sink.append(AudioChunk(samples: Self.tone(seconds: 2)))
        _ = try await sink.finish()

        #expect(log.events == [.recordingVerified(id: id.description, milliseconds: 2_000)])
    }

    @Test("the recording reads back as the samples that were written, to Int16 precision")
    func readsBack() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let samples = Self.tone(seconds: 0.5)
        let sink = try await rig.store.begin(SessionID())
        try await sink.append(AudioChunk(samples: Array(samples[..<4_000])))
        try await sink.append(AudioChunk(samples: Array(samples[4_000...])))
        let recording = try await sink.finish()
        let clip = try await rig.store.load(recording)

        #expect(clip.samples.count == samples.count)
        let worst = zip(clip.samples, samples).map { abs($0 - $1) }.max() ?? 1
        #expect(worst < 0.001)
    }

    @Test("finishing a recording with no samples fails verification, and a damaged file does too")
    func verificationFails() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let sink = try await rig.store.begin(SessionID())
        await #expect(throws: RecordingStoreError.self) { try await sink.finish() }

        try FileManager.default.createDirectory(at: rig.folder, withIntermediateDirectories: true)
        let garbage = rig.folder.appending(path: "garbage.caf")
        try Data("not audio at all".utf8).write(to: garbage)
        let empty = rig.folder.appending(path: "empty.caf")
        try Data().write(to: empty)
        let missing = rig.folder.appending(path: "missing.caf")

        for url in [garbage, empty, missing] {
            #expect(throws: RecordingStoreError.self) { try CAFRecordingStore.verify(url, expectedSamples: 16_000) }
        }
    }

    @Test("a file whose length differs from the samples written fails verification")
    func lengthMismatch() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let sink = try await rig.store.begin(SessionID())
        try await sink.append(AudioChunk(samples: Self.tone(seconds: 1)))
        let recording = try await sink.finish()

        #expect(throws: RecordingStoreError.self) {
            try CAFRecordingStore.verify(recording.url, expectedSamples: 3 * AudioClip.sampleRate)
        }
        #expect(throws: Never.self) {
            try CAFRecordingStore.verify(recording.url, expectedSamples: AudioClip.sampleRate)
        }
    }

    @Test("an aborted recording leaves no file, and delete removes a finished one and forgives a missing one")
    func deleting() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let aborted = SessionID()
        let sink = try await rig.store.begin(aborted)
        try await sink.append(AudioChunk(samples: Self.tone(seconds: 0.5)))
        await sink.abort()
        let abortedURL = rig.folder.appending(path: "\(aborted).caf")
        #expect(!FileManager.default.fileExists(atPath: abortedURL.path))

        let kept = try await rig.store.begin(SessionID())
        try await kept.append(AudioChunk(samples: Self.tone(seconds: 0.5)))
        let recording = try await kept.finish()
        #expect(FileManager.default.fileExists(atPath: recording.url.path))
        try await rig.store.delete(recording.url)
        #expect(!FileManager.default.fileExists(atPath: recording.url.path))
        try await rig.store.delete(recording.url)
    }

    @Test("delete refuses a file outside the recordings folder")
    func deleteStaysInsideFolder() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let outside = FileManager.default.temporaryDirectory.appending(path: "susurro-outside-\(UUID().uuidString).txt")
        try Data("keep me".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        await #expect(throws: RecordingStoreError.self) { try await rig.store.delete(outside) }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("the folder is made on demand, from the provider each time")
    func folderIsCreated() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        #expect(!FileManager.default.fileExists(atPath: rig.folder.path))
        let sink = try await rig.store.begin(SessionID())
        await sink.abort()

        #expect(FileManager.default.fileExists(atPath: rig.folder.path))
    }
}
