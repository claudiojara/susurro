import Domain
import Foundation

/// The style choices of the user, kept in the settings store: the tone of each category under a key of its own, so that
/// one damaged key cannot affect another, and the list of overrides under one key.
public final class SettingsStylePreferences: StylePreferencesStore {
    private let settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    private static let overrides = SettingKey<[StyleOverride]>.json(area: "style", name: "overrides", default: [])

    /// The key of a category's tone. An empty value is a category the user never edited.
    private static func toneKey(_ category: AppCategory) -> SettingKey<String> {
        SettingKey<String>(area: "style", name: "tone_\(category.rawValue)", default: "")
    }

    /// Every key, for the check that none share a storage name.
    public static var keys: [any AnySettingKey] {
        [overrides] + AppCategory.allCases.map { toneKey($0) as any AnySettingKey }
    }

    public func tone(for category: AppCategory) -> Tone {
        edited(category) ?? category.defaultTone
    }

    public func isEdited(_ category: AppCategory) -> Bool {
        edited(category) != nil
    }

    public func setTone(_ tone: Tone, for category: AppCategory) {
        let key = Self.toneKey(category)
        if tone == category.defaultTone {
            settings.remove(key)
        } else {
            settings.set(tone.rawValue, for: key)
        }
    }

    public func overrides() -> [StyleOverride] {
        settings.value(for: Self.overrides)
    }

    public func setOverride(_ override: StyleOverride) {
        var all = overrides()
        let index = all.firstIndex { $0.target == override.target }
        if override.category == nil && override.tone == nil {
            if let index { all.remove(at: index) }
        } else if let index {
            all[index] = override
        } else {
            all.append(override)
        }
        settings.set(all, for: Self.overrides)
    }

    public func removeOverride(for target: StyleTarget) {
        var all = overrides()
        all.removeAll { $0.target == target }
        settings.set(all, for: Self.overrides)
    }

    private func edited(_ category: AppCategory) -> Tone? {
        Tone(rawValue: settings.value(for: Self.toneKey(category)))
    }
}
