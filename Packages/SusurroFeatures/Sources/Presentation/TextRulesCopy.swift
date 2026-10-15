import Domain

/// Why a replacement rule or a snippet was refused, as the Dictionary tab says it.
enum TextRulesCopy {
    static func replacementRefusal(_ error: DictionaryError) -> String? {
        switch error {
        case .empty:
            L10n.string("settings.replacements.empty", "Enter both the spoken and the written form.")
        case .duplicate:
            L10n.string("settings.replacements.duplicate", "That spoken form already has a rule.")
        case .tooLong:
            L10n.string(
                "settings.replacements.tooLong",
                "A form can have at most \(TextRuleLimits.maxPhraseLength) characters.")
        case .notFound: nil
        }
    }

    static func snippetRefusal(_ error: DictionaryError) -> String? {
        switch error {
        case .empty:
            L10n.string("settings.snippets.empty", "Enter a trigger phrase and the text to insert.")
        case .duplicate:
            L10n.string("settings.snippets.duplicate", "Another snippet has that trigger phrase.")
        case .tooLong:
            L10n.string(
                "settings.snippets.tooLong",
                "A trigger can have at most \(TextRuleLimits.maxPhraseLength) characters, and a snippet at most \(TextRuleLimits.maxSnippetLength)."
            )
        case .notFound: nil
        }
    }
}
