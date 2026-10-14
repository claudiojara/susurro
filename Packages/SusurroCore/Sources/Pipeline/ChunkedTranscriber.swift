import Domain

/// Transcribes a clip of any length with a recognizer that takes clips up to a limit: it splits the clip with
/// `AudioChunker`, transcribes the pieces, and joins the transcripts in the order of the pieces, whichever finishes first.
///
/// A cancelled caller stops the pieces that have not started. A piece that fails fails the whole clip, because a
/// transcript with a hole in it would paste as if it were complete.
public struct ChunkedTranscriber: Sendable {
    public let limit: Duration?
    /// How many pieces are transcribed at once. A recognizer that serializes its own inference gains nothing from more.
    public let concurrency: Int

    public init(limit: Duration?, concurrency: Int = 1) {
        self.limit = limit
        self.concurrency = max(1, concurrency)
    }

    /// - Parameter transcribePiece: Transcribes one piece, with whatever limits the caller puts on a single call.
    public func transcribe(
        _ clip: AudioClip,
        using transcribePiece: @escaping @Sendable (AudioClip) async throws -> RawTranscript
    ) async throws -> RawTranscript {
        let pieces = AudioChunker.chunks(of: clip, limit: limit)
        if pieces.count == 1 { return try await transcribePiece(pieces[0]) }

        var texts = [String](repeating: "", count: pieces.count)
        try await withThrowingTaskGroup(of: (index: Int, text: String).self) { group in
            var next = 0
            func startNext() throws {
                try Task.checkCancellation()
                let index = next
                next += 1
                let piece = pieces[index]
                group.addTask { (index, try await transcribePiece(piece).text) }
            }
            while next < min(concurrency, pieces.count) { try startNext() }
            while let finished = try await group.next() {
                texts[finished.index] = finished.text
                if next < pieces.count { try startNext() }
            }
        }
        let joined =
            texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return RawTranscript(text: joined)
    }
}
