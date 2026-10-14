import Domain

/// The user's style settings on top of a `SettingsStore`: the tone of each category, and the overrides for apps and
/// sites. Every value is a setting of its own (no single blob), so a damaged one costs only itself. The keys are
/// `style.tone-<category>` and `style.override-<category|tone>-<bundle|host>-<target>`, where the target has its dots
/// and percent signs escaped, because a key part may not hold a dot. `style.overrideTargets` lists the targets that have
/// an override, in the order they were added, so the settings screen can show them.
public final class StyleSettingsRepository: StylePreferencesStore {
    private let store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    // MARK: Tone of a category

    /// The tone the user chose for the category, or its default.
    public func tone(for category: AppCategory) -> Tone {
        store.value(for: toneKey(category))
    }

    /// Sets the tone of a category. Setting the default tone is the same as never having changed it.
    public func setTone(_ tone: Tone, for category: AppCategory) {
        if tone == category.defaultTone {
            store.remove(toneKey(category))
        } else {
            store.set(tone, for: toneKey(category))
        }
    }

    /// Whether the user changed the tone of the category from the default.
    public func isEdited(_ category: AppCategory) -> Bool {
        tone(for: category) != category.defaultTone
    }

    /// Brings the category back to its default tone.
    public func resetTone(for category: AppCategory) {
        store.remove(toneKey(category))
    }

    // MARK: Overrides

    /// The override stored for exactly this target, or nil when there is none.
    public func override(for target: StyleTarget) -> StyleOverride? {
        let override = StyleOverride(
            category: AppCategory(rawValue: store.value(for: overrideKey("category", target))),
            tone: Tone(rawValue: store.value(for: overrideKey("tone", target))))
        return override.isEmpty ? nil : override
    }

    /// Stores the override for the target. An override that sets nothing removes it.
    public func setOverride(_ override: StyleOverride, for target: StyleTarget) {
        set(override.category?.rawValue, for: overrideKey("category", target))
        set(override.tone?.rawValue, for: overrideKey("tone", target))
        var listed = store.value(for: Self.overrideTargets)
        let name = Self.listName(of: target)
        if override.isEmpty {
            listed.removeAll { $0 == name }
        } else if !listed.contains(name) {
            listed.append(name)
        }
        store.set(listed, for: Self.overrideTargets)
    }

    /// The overrides the user stored, in the order they were added.
    public func overrideEntries() -> [StyleOverrideEntry] {
        store.value(for: Self.overrideTargets).compactMap { name in
            guard let target = Self.target(listedAs: name), let override = override(for: target) else { return nil }
            return StyleOverrideEntry(target: target, override: override)
        }
    }

    public func removeOverride(for target: StyleTarget) {
        setOverride(StyleOverride(), for: target)
    }

    // MARK: For a dictation

    /// The settings a dictation resolves its style with: the tone of every category, and the overrides stored for
    /// `targets`, which are the ones that could apply to the app and page (see `StyleResolver.candidateTargets`).
    public func settings(for targets: [StyleTarget]) -> StyleSettings {
        var tones: [AppCategory: Tone] = [:]
        for category in AppCategory.allCases {
            let tone = tone(for: category)
            if tone != category.defaultTone { tones[category] = tone }
        }
        var overrides: [StyleTarget: StyleOverride] = [:]
        for target in targets {
            if let stored = override(for: target) { overrides[target] = stored }
        }
        return StyleSettings(tones: tones, overrides: overrides)
    }

    // MARK: Keys

    /// The targets that have an override, as `bundle:<id>` or `host:<host>`.
    static let overrideTargets = SettingKey<[String]>.json(area: "style", name: "overrideTargets", default: [])

    static func listName(of target: StyleTarget) -> String {
        switch target {
        case .bundle(let id): "bundle:\(id)"
        case .host(let host): "host:\(host)"
        }
    }

    static func target(listedAs name: String) -> StyleTarget? {
        if name.hasPrefix("bundle:") { return .bundle(String(name.dropFirst("bundle:".count))) }
        if name.hasPrefix("host:") { return .host(String(name.dropFirst("host:".count))) }
        return nil
    }

    private func toneKey(_ category: AppCategory) -> SettingKey<Tone> {
        SettingKey<Tone>(area: "style", name: "tone-\(category.rawValue)", default: category.defaultTone)
    }

    /// An override part is stored as its raw value, and as an empty string when it sets nothing.
    private func overrideKey(_ part: String, _ target: StyleTarget) -> SettingKey<String> {
        let (kind, name): (String, String) =
            switch target {
            case .bundle(let id): ("bundle", Self.escaped(id))
            case .host(let host): ("host", Self.escaped(host))
            }
        return SettingKey<String>(area: "style", name: "override-\(part)-\(kind)-\(name)", default: "")
    }

    private func set(_ raw: String?, for key: SettingKey<String>) {
        if let raw { store.set(raw, for: key) } else { store.remove(key) }
    }

    /// The target without dots, which a key part may not hold. A percent sign is escaped too, so two targets never
    /// share a key.
    static func escaped(_ target: String) -> String {
        target.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: ".", with: "%2E")
    }
}
