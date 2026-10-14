import Foundation

/// Deletes a stored audio file. Deleting a file that is already gone succeeds: the goal is that the file is not there.
public protocol AudioFileDeleting: Sendable {
    func delete(_ url: URL) async throws
}

/// Reads a stored recording back as a clip for the recognizer.
public protocol AudioClipLoading: Sendable {
    func clip(at url: URL) async throws -> AudioClip
}

/// Puts text on the user's clipboard. It is the only way the history hands text out; it never pastes.
public protocol ClipboardWriting: Sendable {
    func copy(_ text: String) async
}

/// The text a reprocessed recording produced.
public struct ReprocessedText: Sendable, Equatable {
    public let rawText: String
    public let cleanedText: String?
    public let finalText: String
    public let asrProvider: ASRProviderID?
    public let cleanerProvider: String?
    public let fallbackReason: String?

    public init(
        rawText: String,
        cleanedText: String? = nil,
        finalText: String,
        asrProvider: ASRProviderID? = nil,
        cleanerProvider: String? = nil,
        fallbackReason: String? = nil
    ) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.finalText = finalText
        self.asrProvider = asrProvider
        self.cleanerProvider = cleanerProvider
        self.fallbackReason = fallbackReason
    }
}

public enum ReprocessOutcome: Sendable, Equatable {
    case text(ReprocessedText)
    case noSpeech
}

/// Runs a stored recording through the pipeline stages again, from voice detection to cleanup, with the category and
/// tone the record kept. It never inserts anything: the caller decides what to do with the text.
public protocol DictationReprocessing: Sendable {
    func reprocess(_ clip: AudioClip, for record: DictationRecord) async throws -> ReprocessOutcome
}
