import Domain

/// Builds the payload a cleaner receives, from what the dictation knows. The locality of the cleaner decides its shape:
/// a cloud cleaner gets a `CloudCleanupRequest`, which cannot hold context, and a local one gets the transcript plus
/// the bounded text before the cursor. The text after the cursor, the selection, and text read from the screen are
/// never part of a payload.
public enum CleanupRequestFactory {
    /// The most characters of text before the cursor a local cleaner is given, nearest the cursor.
    public static let beforeCursorLimit = 500

    public static func payload(for cleaner: any TranscriptCleaner, input: CleanupInput) -> CleanupPayload {
        switch cleaner.locality {
        case .cloud:
            return .cloud(
                CloudCleanupRequest(transcript: input.transcript, style: input.style, vocabulary: input.vocabulary))
        case .local:
            let room = max(0, cleaner.budget.maxInputCharacters - input.transcript.count)
            let before = (input.cursor?.before ?? "").suffix(min(beforeCursorLimit, room))
            return .local(
                LocalCleanupRequest(
                    transcript: input.transcript, style: input.style, vocabulary: input.vocabulary,
                    beforeCursor: String(before)))
        }
    }
}
