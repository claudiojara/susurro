import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// A model that records what the screen asks of it.
@MainActor
private final class SpySettingsModel: SettingsViewModeling {
    var state: SettingsViewState
    private(set) var calls: [String] = []

    init(_ state: SettingsViewState) {
        self.state = state
    }

    func setLanguage(_ id: String) { calls.append("language \(id)") }
    func setInterfaceLanguage(_ id: String) { calls.append("interfaceLanguage \(id)") }
    func setAppContext(_ isOn: Bool) { calls.append("appContext \(isOn)") }
    func setOCR(_ isOn: Bool) { calls.append("ocr \(isOn)") }
    func setCleanup(_ isOn: Bool) { calls.append("cleanup \(isOn)") }
    func setOverlayEdge(_ id: String) { calls.append("edge \(id)") }
    func setOverlayVariant(_ id: String) { calls.append("variant \(id)") }
    func selectProvider(_ id: String) { calls.append("select \(id)") }
    func setProviderEnabled(_ id: String, isOn: Bool) { calls.append("enable \(id) \(isOn)") }
    func setProviderField(_ id: String, field: String, value: String) { calls.append("field \(id) \(field) \(value)") }
    func requestInputMonitoring() async { calls.append("inputMonitoring") }
    func setTone(category: String, tone: String) { calls.append("tone \(category) \(tone)") }
    func addOverride(identifier: String, isSite: Bool, category: String?, tone: String?) {
        calls.append("override \(identifier) \(isSite) \(category ?? "-") \(tone ?? "-")")
    }
    func removeOverride(_ id: String) { calls.append("removeOverride \(id)") }
    func addTerm(_ term: String) { calls.append("addTerm \(term)") }
    func editTerm(_ old: String, to new: String) { calls.append("editTerm \(old) \(new)") }
    func removeTerm(_ term: String) { calls.append("removeTerm \(term)") }
    func addReplacement(spoken: String, written: String) { calls.append("addReplacement \(spoken) \(written)") }
    func editReplacement(_ old: String, spoken: String, written: String) {
        calls.append("editReplacement \(old) \(spoken) \(written)")
    }
    func removeReplacement(_ spoken: String) { calls.append("removeReplacement \(spoken)") }
    func addSnippet(trigger: String, text: String) { calls.append("addSnippet \(trigger) \(text)") }
    func editSnippet(_ old: String, trigger: String, text: String) {
        calls.append("editSnippet \(old) \(trigger) \(text)")
    }
    func removeSnippet(_ trigger: String) { calls.append("removeSnippet \(trigger)") }
    func setRemoveFillers(_ isOn: Bool) { calls.append("removeFillers \(isOn)") }
    func acceptSuggestion(_ id: String) { calls.append("accept \(id)") }
    func dismissSuggestion(_ id: String) { calls.append("dismiss \(id)") }
    func setLearnFromCorrections(_ isOn: Bool) { calls.append("learn \(isOn)") }
    func selectTheme(_ id: String) { calls.append("theme \(id)") }
    func setAppearance(_ id: String) { calls.append("appearance \(id)") }
    func refresh() async { calls.append("refresh") }
    func run() async { calls.append("run") }
    func selectMicrophone(_ id: String) { calls.append("microphone \(id)") }
    func setPauseMedia(_ isOn: Bool) { calls.append("pauseMedia \(isOn)") }
}

@MainActor
@Suite("Settings container")
struct SettingsContainerTests {
    private let size = CGSize(width: 632, height: 512)

    private func png(of view: some View, scheme: ColorScheme = .light) -> Data {
        SnapshotSupport.pngData(of: view.environment(\.staticControls, true), size: size, scheme: scheme)
    }

    @Test("the container draws the state its model has: the screen of that state and no other")
    func drawsTheModelsState() {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let container = SettingsContainer(model: model) { EmptyView() }
        let screen = SettingsScreen(state: SettingsFixtures.screen, actions: .none) { EmptyView() }

        #expect(png(of: container) == png(of: screen))
    }

    @Test("a model that has another state is drawn differently")
    func followsTheModel() {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let before = png(of: SettingsContainer(model: model) { EmptyView() })

        model.state = SettingsViewState(
            general: SettingsFixtures.generalPinned, providers: SettingsFixtures.providers,
            hotkey: SettingsFixtures.hotkey, style: SettingsFixtures.style, dictionary: SettingsFixtures.dictionary,
            appearance: SettingsFixtures.appearance)

        #expect(png(of: SettingsContainer(model: model) { EmptyView() }) != before)
    }

    @Test("the audio actions reach the intents of the model")
    func audioActionsReachTheModel() {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let actions = SettingsActions(model: model)

        actions.audio.microphone("yeti")
        actions.audio.pauseMedia(true)

        #expect(model.calls == ["microphone yeti", "pauseMedia true"])
    }

    @Test("every action of the screen reaches the intent of the model that it names")
    func actionsReachTheModel() async {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let actions = SettingsActions(model: model)

        actions.general.language("es")
        actions.general.appContext(false)
        actions.general.ocr(true)
        actions.general.cleanup(false)
        actions.general.edge("top")
        actions.general.variant("compact")
        actions.providers.select("deepgram")
        actions.providers.setEnabled("deepgram", true)
        actions.providers.setField("local-whisper", "endpoint", "http://localhost:1")
        actions.style.setTone("email", "casual")
        actions.style.addOverride("com.apple.Notes", false, nil, "casual")
        actions.style.removeOverride("app:com.apple.Notes")
        actions.dictionary.add("Acme")
        actions.dictionary.edit("Acme", "ACME")
        actions.dictionary.remove("ACME")
        actions.appearance.theme("ocean")
        actions.appearance.mode("dark")
        actions.hotkey.requestInputMonitoring()
        for _ in 0..<20 { await Task.yield() }

        #expect(
            model.calls == [
                "language es", "appContext false", "ocr true", "cleanup false", "edge top", "variant compact",
                "select deepgram", "enable deepgram true", "field local-whisper endpoint http://localhost:1",
                "tone email casual", "override com.apple.Notes false - casual", "removeOverride app:com.apple.Notes",
                "addTerm Acme", "editTerm Acme ACME", "removeTerm ACME", "theme ocean", "appearance dark",
                "inputMonitoring",
            ])
    }

    @Test("the actions of the replacement rules, the snippets, and the filler switch reach the model")
    func textRuleActionsReachTheModel() {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let actions = SettingsActions(model: model).dictionary

        actions.addReplacement("jira", "Jira")
        actions.editReplacement("jira", "jira", "JIRA")
        actions.removeReplacement("jira")
        actions.addSnippet("firma", "Claudio")
        actions.editSnippet("firma", "mi firma", "Claudio J.")
        actions.removeSnippet("mi firma")
        actions.removeFillers(false)

        #expect(
            model.calls == [
                "addReplacement jira Jira", "editReplacement jira jira JIRA", "removeReplacement jira",
                "addSnippet firma Claudio", "editSnippet firma mi firma Claudio J.", "removeSnippet mi firma",
                "removeFillers false",
            ])
    }

    @Test("the actions of the suggested terms reach the model")
    func suggestionActionsReachTheModel() {
        let model = SpySettingsModel(SettingsFixtures.screen)
        let actions = SettingsActions(model: model).dictionary

        actions.acceptSuggestion("kaelthorn")
        actions.dismissSuggestion("shaun")
        actions.learnFromCorrections(false)

        #expect(model.calls == ["accept kaelthorn", "dismiss shaun", "learn false"])
    }

    @Test("each level of a provider's status has a tint of its own")
    func statusTints() {
        let tints = [ProviderStatusState.Level.ready, .pending, .warning, .error].map(\.tint)
        #expect(tints == [.success, .pending, .warning, .error])
    }

    @Test("the tabs are the six sections, in the order of the window")
    func tabs() {
        #expect(
            SettingsTab.allCases.map(\.title) == [
                "General", "Providers", "Hotkey", "Style", "Dictionary", "Appearance",
            ])
    }
}
