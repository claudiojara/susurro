import CoreTestSupport
import DesignSystem
import Domain
import Foundation
import Settings
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Style, dictionary, and appearance settings", .timeLimit(.minutes(1)))
struct StyleSettingsViewModelTests {
    // MARK: Style table

    @Test("the table shows the default tone of every category")
    func defaultTable() {
        let style = SettingsRig().model().state.style
        let tones = Dictionary(uniqueKeysWithValues: style.rows.map { ($0.id, $0.toneID) })
        #expect(
            tones == [
                "email": "formal", "work_chat": "casual", "personal_messaging": "veryCasual", "document": "neutral",
                "terminal": "verbatim", "ai_chat": "neutral", "other": "neutral",
            ])
        #expect(style.rows.allSatisfy { !$0.isEdited })
        #expect(style.toneChoices.map(\.id) == ["formal", "neutral", "casual", "veryCasual", "verbatim"])
        #expect(style.categoryChoices.count == 7)
    }

    @Test("editing email to casual persists and is reflected after a relaunch")
    func editedTable() {
        let rig = SettingsRig()
        rig.model().setTone(category: "email", tone: "casual")
        let relaunched = rig.model().state.style
        let email = relaunched.rows.first { $0.id == "email" }
        #expect(email?.toneID == "casual")
        #expect(email?.isEdited == true)
        #expect(relaunched.rows.first { $0.id == "work_chat" }?.isEdited == false)
        #expect(SettingsStylePreferences(settings: rig.settings).tone(for: .email) == .casual)
    }

    @Test("a category or a tone nobody knows changes nothing")
    func unknownTone() {
        let rig = SettingsRig()
        let model = rig.model()
        model.setTone(category: "email", tone: "shouting")
        model.setTone(category: "nope", tone: "casual")
        #expect(model.state.style.rows.allSatisfy { !$0.isEdited })
    }

    // MARK: Overrides

    @Test("overrides of category only, tone only, and both are listed and removable")
    func overrides() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addOverride(
            identifier: "com.tinyspeck.slackmacgap", isSite: false, category: "personal_messaging", tone: nil)
        model.addOverride(identifier: "com.apple.Notes", isSite: false, category: nil, tone: "casual")
        model.addOverride(identifier: "docs.google.com", isSite: true, category: "document", tone: "formal")
        let overrides = model.state.style.overrides
        #expect(overrides.map(\.kind) == ["App", "App", "Site"])
        #expect(
            overrides.map(\.summary) == [
                "Category: Personal messaging", "Tone: Casual", "Category: Document, Tone: Formal",
            ])
        #expect(model.state.style.overrideError == nil)

        model.removeOverride(overrides[1].id)
        #expect(model.state.style.overrides.map(\.identifier) == ["com.tinyspeck.slackmacgap", "docs.google.com"])
    }

    @Test("a site is stored by its host: a pasted address, any case, and www are reduced")
    func siteHost() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addOverride(
            identifier: "https://WWW.Mail.Google.com/mail/u/0", isSite: true, category: "email", tone: nil)
        #expect(model.state.style.overrides.map(\.identifier) == ["mail.google.com"])
        model.addOverride(identifier: "mail.google.com", isSite: true, category: nil, tone: "casual")
        #expect(model.state.style.overrides.count == 1)
        #expect(model.state.style.overrides.first?.summary == "Tone: Casual")
    }

    @Test("an override without a target or without a change is refused with a reason")
    func refusedOverrides() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addOverride(identifier: "  ", isSite: false, category: "email", tone: nil)
        #expect(model.state.style.overrideError == "Enter a bundle id or a website.")
        model.addOverride(identifier: "com.apple.Notes", isSite: false, category: nil, tone: nil)
        #expect(model.state.style.overrideError == "Choose a category, a tone, or both.")
        #expect(model.state.style.overrides.isEmpty)
        model.addOverride(identifier: "com.apple.Notes", isSite: false, category: nil, tone: "casual")
        #expect(model.state.style.overrideError == nil)
    }

    // MARK: Dictionary

    @Test("dictionary terms are added, edited, and removed, and they persist")
    func dictionary() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addTerm("Acme")
        model.addTerm("Maria Gonzalez")
        model.addTerm("kubectl")
        model.editTerm("Acme", to: "ACME Corp")
        model.removeTerm("kubectl")
        #expect(rig.model().state.dictionary.terms == ["ACME Corp", "Maria Gonzalez"])
        #expect(model.state.dictionary.error == nil)
    }

    @Test("an empty, repeated, or too long term is refused with a reason and nothing is stored")
    func dictionaryErrors() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addTerm("Acme")
        model.addTerm("  ")
        #expect(model.state.dictionary.error == "Enter a word or a name.")
        model.addTerm("ACME")
        #expect(model.state.dictionary.error == "That term is already in the dictionary.")
        model.addTerm(String(repeating: "a", count: 41))
        #expect(model.state.dictionary.error == "A term can have at most 40 characters.")
        #expect(model.state.dictionary.terms == ["Acme"])
        model.addTerm("Globex")
        #expect(model.state.dictionary.error == nil)
    }

    // MARK: Appearance

    @Test("the themes are the bundled one and the files of the folder, and the default is selected")
    func themes() async {
        let rig = SettingsRig()
        let model = rig.model()
        await model.refresh()
        let appearance = model.state.appearance
        #expect(appearance.themes.map(\.id) == ["default", "ocean"])
        #expect(appearance.themes.map(\.title) == ["Default", "ocean"])
        #expect(appearance.selectedTheme == "default")
        #expect(appearance.modes.map(\.id) == ["system", "light", "dark"])
        #expect(appearance.selectedMode == "system")
    }

    @Test("selecting a theme applies it without a relaunch and remembers it")
    func selectTheme() async {
        let rig = SettingsRig()
        let model = rig.model()
        await model.refresh()
        model.selectTheme("ocean")
        await model.themeSelection?.value
        #expect(rig.themes.selected == ["ocean"])
        #expect(rig.settings.value(for: AppearanceSettings.theme) == "ocean")
        #expect(model.state.appearance.selectedTheme == "ocean")
    }

    @Test("a chosen theme whose file is gone stays in the list")
    func missingTheme() async {
        let rig = SettingsRig()
        rig.settings.set("old", for: AppearanceSettings.theme)
        let model = rig.model()
        await model.refresh()
        #expect(model.state.appearance.themes.map(\.id).contains("old"))
        #expect(model.state.appearance.selectedTheme == "old")
    }

    @Test("light, dark, and the system's choice re-resolve the colors at once and persist")
    func appearanceMode() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(rig.themeModel.appearance == .system)
        model.setAppearance("dark")
        #expect(rig.themeModel.appearance == .dark)
        #expect(rig.settings.value(for: AppearanceSettings.mode) == .dark)
        model.setAppearance("light")
        #expect(rig.themeModel.appearance == .light)
        model.setAppearance("sepia")
        #expect(rig.themeModel.appearance == .light)
        model.setAppearance("system")
        #expect(rig.themeModel.appearance == .system)
        #expect(model.state.appearance.selectedMode == "system")
    }

    @Test("a theme file that could not be used is reported")
    func themeError() async {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.appearance.themeError == nil)
        let broken = ThemeLoader.load(data: Data(#"{"schemaVersion": 1, "colours": {}}"#.utf8))
        await rig.themeModel.follow(
            AsyncStream { continuation in
                continuation.yield(broken)
                continuation.finish()
            })
        #expect(model.state.appearance.themeError?.contains("colours") == true)
    }
}
