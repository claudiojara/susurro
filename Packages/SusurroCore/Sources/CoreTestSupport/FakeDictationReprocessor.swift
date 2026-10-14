import Domain
import Synchronization

/// A reprocessor with a scripted result. It logs the records it was given, and a `gated` one suspends until
/// `release()`, after signalling `entered`.
public final class FakeDictationReprocessor: DictationReprocessing {
    public let entered = Gate()
    private let result: Mutex<Result<ReprocessOutcome, any Error>>
    private let records = Mutex<[DictationRecord]>([])
    private let clips = Mutex<[AudioClip]>([])
    private let gate: Gate?

    public init(result: Result<ReprocessOutcome, any Error>, gated: Bool = false) {
        self.result = Mutex(result)
        gate = gated ? Gate() : nil
    }

    public convenience init(text: String, gated: Bool = false) {
        self.init(result: .success(.text(ReprocessedText(rawText: text, finalText: text))), gated: gated)
    }

    /// The records it was asked to reprocess, in order.
    public var reprocessedRecords: [DictationRecord] { records.withLock { $0 } }
    public var reprocessedClips: [AudioClip] { clips.withLock { $0 } }

    public func setResult(_ result: Result<ReprocessOutcome, any Error>) {
        self.result.withLock { $0 = result }
    }

    public func release() { gate?.open() }

    public func reprocess(_ clip: AudioClip, for record: DictationRecord) async throws -> ReprocessOutcome {
        records.withLock { $0.append(record) }
        clips.withLock { $0.append(clip) }
        entered.open()
        await gate?.wait()
        try Task.checkCancellation()
        return try result.withLock { $0 }.get()
    }
}
