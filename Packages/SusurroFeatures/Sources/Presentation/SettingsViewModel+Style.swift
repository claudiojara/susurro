import Domain
import Foundation
import SusurroUI

extension SettingsViewModel {
    // MARK: Style table and overrides

    var styleState: StyleSettingsState {
        let style = dependencies.style
        return StyleSettingsState(
            rows: AppCategory.allCases.map {
                StyleRowState(
                    id: $0.rawValue, title: SettingsCopy.category($0), toneID: style.tone(for: $0).rawValue,
                    isEdited: style.isEdited($0))
            },
            toneChoices: Tone.allCases.map { SettingsChoice(id: $0.rawValue, title: SettingsCopy.tone($0)) },
            categoryChoices: AppCategory.allCases.map {
                SettingsChoice(id: $0.rawValue, title: SettingsCopy.category($0))
            },
            overrides: style.overrideEntries().map(Self.row(for:)),
            overrideError: overrideError
        )
    }

    private static func row(for entry: StyleOverrideEntry) -> StyleOverrideRowState {
        let kind: String
        let id: String
        let identifier: String
        switch entry.target {
        case .bundle(let bundleID):
            kind = "App"
            id = "app:\(bundleID)"
            identifier = bundleID
        case .host(let host):
            kind = "Site"
            id = "site:\(host)"
            identifier = host
        }
        return StyleOverrideRowState(
            id: id, kind: kind, identifier: identifier,
            summary: SettingsCopy.overrideSummary(category: entry.override.category, tone: entry.override.tone))
    }

    public func setTone(category: String, tone: String) {
        guard let category = AppCategory(rawValue: category), let tone = Tone(rawValue: tone) else { return }
        dependencies.style.setTone(tone, for: category)
        changed()
    }

    public func addOverride(identifier: String, isSite: Bool, category: String?, tone: String?) {
        let category = category.flatMap(AppCategory.init(rawValue:))
        let tone = tone.flatMap(Tone.init(rawValue:))
        let target = isSite ? Self.host(of: identifier).map { StyleTarget.host($0) } : Self.bundleID(identifier)
        guard let target else {
            overrideError = SettingsCopy.noOverrideTarget
            changed()
            return
        }
        guard category != nil || tone != nil else {
            overrideError = SettingsCopy.noOverrideChange
            changed()
            return
        }
        overrideError = nil
        dependencies.style.setOverride(StyleOverride(category: category, tone: tone), for: target)
        changed()
    }

    public func removeOverride(_ id: String) {
        guard let entry = dependencies.style.overrideEntries().first(where: { Self.row(for: $0).id == id }) else {
            return
        }
        dependencies.style.removeOverride(for: entry.target)
        changed()
    }

    private static func bundleID(_ text: String) -> StyleTarget? {
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty || id.contains(where: \.isWhitespace) ? nil : .bundle(id)
    }

    /// The host of a site as the user typed it: a bare host, or a whole address pasted from the browser. Case is ignored
    /// and `www.` is dropped, as the resolver does when it matches.
    private static func host(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var host = URLComponents(string: withScheme)?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: Dictionary

    var dictionaryState: DictionarySettingsState {
        DictionarySettingsState(terms: dependencies.dictionary.terms(), error: dictionaryError)
    }

    public func addTerm(_ term: String) {
        perform { try dependencies.dictionary.add(term) }
    }

    public func editTerm(_ old: String, to new: String) {
        perform { try dependencies.dictionary.edit(old, to: new) }
    }

    public func removeTerm(_ term: String) {
        dependencies.dictionary.remove(term)
        dictionaryError = nil
        changed()
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            dictionaryError = nil
        } catch let error as DictionaryError {
            dictionaryError =
                switch error {
                case .empty: SettingsCopy.emptyTerm
                case .duplicate: SettingsCopy.duplicateTerm
                case .tooLong: SettingsCopy.termTooLong(VocabularyLimits.maxTermLength)
                case .notFound: nil
                }
        } catch {
            dictionaryError = SettingsCopy.emptyTerm
        }
        changed()
    }
}
