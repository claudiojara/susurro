import Domain
import Synchronization
import TextShaping

/// What the coordinator needs to build the vocabulary of a dictation: the user's dictionary, the builder that merges it
/// with the names found around the cursor, and, when the user turned OCR on, the reading of the screen.
public struct VocabularyPipeline: Sendable {
    let dictionary: any UserDictionary
    let builder: VocabularyBuilder
    let enrichment: ContextEnrichment?

    public init(dictionary: any UserDictionary, builder: VocabularyBuilder, enrichment: ContextEnrichment? = nil) {
        self.dictionary = dictionary
        self.builder = builder
        self.enrichment = enrichment
    }
}

/// The vocabulary work of one dictation. It starts as the key goes down, beside the capture of the context: the screen is
/// read while the user speaks, once the context says the field is not a secure one, and the reading is used only if it
/// has finished by the time the vocabulary is built. Like the context, it belongs to its dictation alone.
struct VocabularyJob: Sendable {
    /// The lines read from the screen, once the reading has finished. Nil until then, and for good if it is dropped.
    private final class ScreenReading: Sendable {
        private let lines = Mutex<[String]?>(nil)
        var value: [String]? { lines.withLock { $0 } }
        func finish(with value: [String]) { lines.withLock { $0 = value } }
    }

    private let pipeline: VocabularyPipeline
    private let reading: ScreenReading
    private let task: Task<Void, Never>?

    /// Starts reading the screen at a low priority, when OCR can be used, and returns at once.
    init(context: ContextJob?, pipeline: VocabularyPipeline) {
        let reading = ScreenReading()
        self.pipeline = pipeline
        self.reading = reading
        if let enrichment = pipeline.enrichment, let context {
            task = Task(priority: .utility) {
                let captured = await context.capturedContext()
                guard let app = captured.app else { return }
                let lines = await enrichment.screenText(
                    for: ScreenTarget(app: app, windowTitle: captured.windowTitle),
                    isSecureField: captured.isSecureField)
                if !Task.isCancelled { reading.finish(with: lines) }
            }
        } else {
            task = nil
        }
    }

    /// Drops the reading. A reading that ignores the cancellation still finishes, and its lines are not used.
    func cancel() {
        task?.cancel()
    }

    /// The vocabulary now. The dictionary is always in it. The names around the cursor are in it when the context was
    /// captured, and the names on the screen when the reading has finished. Nothing is extracted from a secure field.
    func terms(for context: DictationContext?) -> [String] {
        pipeline.builder.build(
            VocabularySources(
                dictionary: pipeline.dictionary.terms(),
                beforeCursor: context?.beforeCursor ?? "",
                afterCursor: context?.afterCursor ?? "",
                selection: context?.selection ?? "",
                screenText: reading.value ?? [],
                isSecureField: context?.isSecureField ?? false))
    }
}
