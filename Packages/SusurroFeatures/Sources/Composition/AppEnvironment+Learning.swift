import Domain
import Pipeline
import TextShaping

extension AppEnvironment {
    /// What the learning dictionary reads: the focused field, read again after a paste, and the tagger that tells a name.
    public struct CorrectionSources: Sendable {
        public var reader: any FocusedContextReader
        public var tagger: any EntityTagger

        public init(reader: any FocusedContextReader, tagger: any EntityTagger) {
            self.reader = reader
            self.tagger = tagger
        }
    }
}

extension AppEnvironment.Dependencies {
    /// The watch that suggests the words the user corrects after a dictation, or nil when the graph has no field reader
    /// or no frontmost app to check. Its suggestions and the dismissed terms are settings of the dictionary area.
    func correctionWatch(sleep: @escaping @Sendable (Duration) async throws -> Void) -> CorrectionWatch? {
        guard let corrections, let frontmost else { return nil }
        let settings = settings
        return CorrectionWatch(
            reader: corrections.reader, frontmost: frontmost, store: SuggestionStore(settings: settings),
            dictionaryTerms: { settings.value(for: DictionarySettings.terms) },
            filter: SuggestionFilter(tagger: corrections.tagger), settings: settings, dates: history.dates,
            diagnostics: diagnostics, sleep: sleep)
    }
}
