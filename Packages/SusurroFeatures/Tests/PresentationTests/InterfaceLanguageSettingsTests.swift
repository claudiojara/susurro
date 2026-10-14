import CoreTestSupport
import DesignSystem
import Domain
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Interface language setting", .timeLimit(.minutes(1)))
struct InterfaceLanguageSettingsTests {
    @Test("the choices are System, English and Español, and System is picked until the user picks another")
    func defaults() {
        let state = SettingsRig().model().state.general
        #expect(state.interfaceLanguages.map(\.id) == ["system", "en", "es"])
        #expect(state.interfaceLanguages.map(\.title) == ["System", "English", "Español"])
        #expect(state.selectedInterfaceLanguage == "system")
    }

    @Test("a pick is stored, applied to the app at once, and leaves the dictation language alone")
    func pick() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setInterfaceLanguage("es")
        #expect(rig.settings.value(for: GeneralSettings.interfaceLanguage) == .spanish)
        #expect(model.state.general.selectedInterfaceLanguage == "es")
        #expect(rig.appliedLanguages.values == [.spanish])
        #expect(rig.settings.value(for: SpeechSettings.languageMode) == .guaranteedSpanish)
        model.setInterfaceLanguage("system")
        #expect(rig.appliedLanguages.values == [.spanish, .system])
    }

    @Test("an unknown id changes nothing")
    func unknown() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setInterfaceLanguage("klingon")
        #expect(rig.settings.value(for: GeneralSettings.interfaceLanguage) == .system)
        #expect(rig.appliedLanguages.values.isEmpty)
    }

    @Test("in Spanish the choices keep the names of the languages, and the dictation labels are translated")
    func spanishLabels() {
        InterfaceLocale.$override.withValue("es") {
            let state = SettingsRig().model().state.general
            #expect(state.interfaceLanguages.map(\.title) == ["Sistema", "English", "Español"])
            #expect(state.languages.map(\.title) == ["Rápido (idioma automático)", "Siempre español"])
        }
    }
}
