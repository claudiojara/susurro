import CoreTestSupport
import Domain
import Foundation
import Settings
import SusurroUI
import Testing

@testable import Presentation

@MainActor
@Suite("Replacement rules, snippets, and filler settings", .timeLimit(.minutes(1)))
struct TextRulesSettingsViewModelTests {
    @Test("replacement rules are added, edited, and removed, and they persist")
    func replacements() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addReplacement(spoken: "jira", written: "Jira")
        model.addReplacement(spoken: "github", written: "GitHub")
        model.editReplacement("jira", spoken: "jira", written: "JIRA")
        model.removeReplacement("github")
        #expect(rig.model().state.dictionary.replacements == [ReplacementRowState(spoken: "jira", written: "JIRA")])
        #expect(
            rig.settings.value(for: TextRuleSettings.replacements) == [ReplacementRule(spoken: "jira", written: "JIRA")]
        )
        #expect(model.state.dictionary.replacementError == nil)
    }

    @Test("an incomplete, repeated, or too long rule is refused with a reason")
    func replacementErrors() {
        let model = SettingsRig().model()
        model.addReplacement(spoken: "jira", written: " ")
        #expect(model.state.dictionary.replacementError == "Enter both the spoken and the written form.")
        model.addReplacement(spoken: "jira", written: "Jira")
        model.addReplacement(spoken: "JIRA", written: "x")
        #expect(model.state.dictionary.replacementError == "That spoken form already has a rule.")
        model.addReplacement(spoken: String(repeating: "a", count: 81), written: "x")
        #expect(model.state.dictionary.replacementError == "A form can have at most 80 characters.")
        model.addReplacement(spoken: "github", written: "GitHub")
        #expect(model.state.dictionary.replacementError == nil)
        #expect(model.state.dictionary.error == nil)
    }

    @Test("snippets are added, edited, and removed, and they persist")
    func snippets() {
        let rig = SettingsRig()
        let model = rig.model()
        model.addSnippet(trigger: "firma", text: "Un saludo,\nClaudio")
        model.editSnippet("firma", trigger: "mi firma", text: "Un saludo,\nClaudio")
        #expect(
            rig.model().state.dictionary.snippets == [SnippetRowState(trigger: "mi firma", text: "Un saludo,\nClaudio")]
        )
        model.removeSnippet("mi firma")
        #expect(model.state.dictionary.snippets.isEmpty)
        #expect(model.state.dictionary.snippetError == nil)
    }

    @Test("an incomplete, repeated, or too long snippet is refused with a reason")
    func snippetErrors() {
        let model = SettingsRig().model()
        model.addSnippet(trigger: "", text: "x")
        #expect(model.state.dictionary.snippetError == "Enter a trigger phrase and the text to insert.")
        model.addSnippet(trigger: "firma", text: "Claudio")
        model.addSnippet(trigger: "Firma", text: "Otro")
        #expect(model.state.dictionary.snippetError == "Another snippet has that trigger phrase.")
        model.addSnippet(trigger: "largo", text: String(repeating: "a", count: 2_001))
        #expect(
            model.state.dictionary.snippetError
                == "A trigger can have at most 80 characters, and a snippet at most 2,000.")
    }

    @Test("filler removal is on by default, and the switch is stored")
    func fillers() {
        let rig = SettingsRig()
        let model = rig.model()
        #expect(model.state.dictionary.removesFillers)
        model.setRemoveFillers(false)
        #expect(model.state.dictionary.removesFillers == false)
        #expect(rig.settings.value(for: TextRuleSettings.removeFillers) == false)
    }
}
