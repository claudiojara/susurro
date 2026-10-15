import CoreTestSupport
import Domain
import Foundation
import Pipeline
import Settings
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Suggested terms settings", .timeLimit(.minutes(1)))
struct SuggestionSettingsViewModelTests {
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func seed(_ rig: SettingsRig) {
        let store = SuggestionStore(settings: rig.settings)
        store.record(term: "Shaun", heard: "Sean", at: Self.day)
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day.addingTimeInterval(60))
        store.record(term: "Kaelthorn", heard: "Kyle Thorn", at: Self.day.addingTimeInterval(120))
    }

    @Test("the suggestions are listed most seen first, then newest, and learning is on by default")
    func listed() {
        let rig = SettingsRig()
        seed(rig)

        let state = rig.model().state.dictionary

        #expect(
            state.suggestions == [
                SuggestionRowState(term: "Kaelthorn", heard: "Kyle Thorn", count: 2),
                SuggestionRowState(term: "Shaun", heard: "Sean", count: 1),
            ])
        #expect(state.learnsFromCorrections)
    }

    @Test("accepting adds the term to the dictionary, which feeds the vocabulary, and drops the suggestion")
    func accept() {
        let rig = SettingsRig()
        seed(rig)
        let model = rig.model()

        model.acceptSuggestion("kaelthorn")

        #expect(rig.settings.value(for: DictionarySettings.terms) == ["Kaelthorn"])
        #expect(DictionaryStore(settings: rig.settings).vocabularyTerms() == ["Kaelthorn"])
        #expect(model.state.dictionary.terms == ["Kaelthorn"])
        #expect(model.state.dictionary.suggestions.map(\.term) == ["Shaun"])
    }

    @Test("accepting a term the dictionary has already only drops the suggestion")
    func acceptDuplicate() {
        let rig = SettingsRig()
        seed(rig)
        rig.settings.set(["kaelthorn"], for: DictionarySettings.terms)
        let model = rig.model()

        model.acceptSuggestion("kaelthorn")

        #expect(rig.settings.value(for: DictionarySettings.terms) == ["kaelthorn"])
        #expect(model.state.dictionary.suggestions.map(\.term) == ["Shaun"])
        #expect(model.state.dictionary.error == nil)
    }

    @Test("dismissing drops the suggestion and keeps the term out for good")
    func dismiss() {
        let rig = SettingsRig()
        seed(rig)
        let model = rig.model()

        model.dismissSuggestion("shaun")

        #expect(model.state.dictionary.suggestions.map(\.term) == ["Kaelthorn"])
        #expect(rig.settings.value(for: DictionarySettings.dismissed) == ["Shaun"])
        #expect(rig.settings.value(for: DictionarySettings.terms).isEmpty)
    }

    @Test("the switch turns learning from corrections off and on")
    func toggle() {
        let rig = SettingsRig()
        let model = rig.model()

        model.setLearnFromCorrections(false)
        #expect(!rig.settings.value(for: DictionarySettings.learnFromCorrections))
        #expect(!model.state.dictionary.learnsFromCorrections)
        model.setLearnFromCorrections(true)
        #expect(rig.settings.value(for: DictionarySettings.learnFromCorrections))
    }
}
