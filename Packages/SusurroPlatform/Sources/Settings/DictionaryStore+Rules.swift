import Domain
import Foundation

// The replacement rules and the voice snippets: each is one list under one setting, like the terms. A rule is known by
// its spoken form and a snippet by its trigger, with case and accents ignored, so two of them cannot answer to one
// phrase.
extension DictionaryStore {
    // MARK: Replacements

    public func replacements() -> [ReplacementRule] {
        settings.value(for: TextRuleSettings.replacements)
    }

    public func addReplacement(_ rule: ReplacementRule) throws {
        let rule = try Self.validated(rule)
        try edit(TextRuleSettings.replacements) { rules in
            guard Self.index(of: rule.spoken, in: rules, by: \.spoken) == nil else { throw DictionaryError.duplicate }
            rules.append(rule)
        }
    }

    public func editReplacement(_ spoken: String, to rule: ReplacementRule) throws {
        let rule = try Self.validated(rule)
        try edit(TextRuleSettings.replacements) { rules in
            guard let index = Self.index(of: spoken, in: rules, by: \.spoken) else { return }
            var others = rules
            others.remove(at: index)
            guard Self.index(of: rule.spoken, in: others, by: \.spoken) == nil else { throw DictionaryError.duplicate }
            rules[index] = rule
        }
    }

    public func removeReplacement(_ spoken: String) {
        try? edit(TextRuleSettings.replacements) { rules in
            if let index = Self.index(of: spoken, in: rules, by: \.spoken) { rules.remove(at: index) }
        }
    }

    /// The terms, then the written forms that have a letter in them and are not a term already.
    public func vocabularyTerms() -> [String] {
        var result = terms()
        var seen = Set(result.map { $0.lowercased() })
        for rule in replacements() where rule.written.contains(where: \.isLetter) {
            if seen.insert(rule.written.lowercased()).inserted { result.append(rule.written) }
        }
        return result
    }

    // MARK: Snippets

    public func snippets() -> [VoiceSnippet] {
        settings.value(for: TextRuleSettings.snippets)
    }

    public func addSnippet(_ snippet: VoiceSnippet) throws {
        let snippet = try Self.validated(snippet)
        try edit(TextRuleSettings.snippets) { snippets in
            guard Self.index(of: snippet.trigger, in: snippets, by: \.trigger) == nil else {
                throw DictionaryError.duplicate
            }
            snippets.append(snippet)
        }
    }

    public func editSnippet(_ trigger: String, to snippet: VoiceSnippet) throws {
        let snippet = try Self.validated(snippet)
        try edit(TextRuleSettings.snippets) { snippets in
            guard let index = Self.index(of: trigger, in: snippets, by: \.trigger) else { return }
            var others = snippets
            others.remove(at: index)
            guard Self.index(of: snippet.trigger, in: others, by: \.trigger) == nil else {
                throw DictionaryError.duplicate
            }
            snippets[index] = snippet
        }
    }

    public func removeSnippet(_ trigger: String) {
        try? edit(TextRuleSettings.snippets) { snippets in
            if let index = Self.index(of: trigger, in: snippets, by: \.trigger) { snippets.remove(at: index) }
        }
    }

    // MARK: Rules

    private static func validated(_ rule: ReplacementRule) throws -> ReplacementRule {
        ReplacementRule(
            spoken: try validated(rule.spoken, limit: TextRuleLimits.maxPhraseLength),
            written: try validated(rule.written, limit: TextRuleLimits.maxPhraseLength))
    }

    private static func validated(_ snippet: VoiceSnippet) throws -> VoiceSnippet {
        VoiceSnippet(
            trigger: try validated(snippet.trigger, limit: TextRuleLimits.maxPhraseLength),
            text: try validated(snippet.text, limit: TextRuleLimits.maxSnippetLength))
    }

    private static func validated(_ text: String, limit: Int) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.empty }
        guard trimmed.count <= limit else { throw DictionaryError.tooLong }
        return trimmed
    }

    private static func index<Item>(of phrase: String, in items: [Item], by key: KeyPath<Item, String>) -> Int? {
        let wanted = folded(phrase)
        return items.firstIndex { folded($0[keyPath: key]) == wanted }
    }

    /// The phrase as the passes compare it: case and accents ignored, ñ kept apart from n.
    private static func folded(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(separator: "ñ", omittingEmptySubsequences: false)
            .map { $0.folding(options: [.diacriticInsensitive], locale: nil) }
            .joined(separator: "ñ")
    }
}
