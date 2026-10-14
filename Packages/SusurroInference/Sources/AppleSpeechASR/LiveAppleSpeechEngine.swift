import AVFoundation
import Foundation
import Speech

/// Runs the system's `SpeechAnalyzer` with a `SpeechTranscriber` for one clip at a time. It needs the language assets and
/// the framework, so it is covered by the opt-in real-model check, not by unit tests.
struct LiveAppleSpeechEngine: AppleSpeechEngine {
    enum EngineError: Error {
        case unsupportedLanguage
        case noAudioFormat
        case conversionFailed
    }

    func isSupported(language: String) async -> Bool {
        await supportedLocale(for: language) != nil
    }

    func install(language: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let locale = try await requireLocale(for: language)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return  // the assets are installed already
        }
        let watching = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watching.cancel() }
        try await request.downloadAndInstall()
    }

    func transcribe(_ samples: [Float], language: String) async throws -> String {
        let locale = try await requireLocale(for: language)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.noAudioFormat
        }
        let input = try Self.buffer(samples, as: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let collecting = Task {
            var pieces: [String] = []
            for try await result in transcriber.results {
                let piece = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
            }
            return pieces.joined(separator: " ")
        }
        return try await withTaskCancellationHandler {
            do {
                try await analyzer.start(inputSequence: inputs)
                feed.yield(AnalyzerInput(buffer: input))
                feed.finish()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                return try await collecting.value
            } catch {
                feed.finish()
                collecting.cancel()
                throw error
            }
        } onCancel: {
            feed.finish()
            collecting.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func supportedLocale(for language: String) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
    }

    private func requireLocale(for language: String) async throws -> Locale {
        guard let locale = await supportedLocale(for: language) else { throw EngineError.unsupportedLanguage }
        return locale
    }

    /// The samples as a buffer in the format the analyzer asked for.
    private static func buffer(_ samples: [Float], as target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard
            let source = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = input.floatChannelData?[0]
        else { throw EngineError.conversionFailed }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        input.frameLength = AVAudioFrameCount(samples.count)
        if source == target { return input }

        guard let converter = AVAudioConverter(from: source, to: target) else { throw EngineError.conversionFailed }
        let ratio = target.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw EngineError.conversionFailed
        }
        nonisolated(unsafe) var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, failure == nil else { throw EngineError.conversionFailed }
        return output
    }
}
