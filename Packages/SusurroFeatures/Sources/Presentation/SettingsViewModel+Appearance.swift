import DesignSystem
import Domain
import SusurroUI

extension SettingsViewModel {
    var appearanceState: AppearanceSettingsState {
        let selected = settings.value(for: AppearanceSettings.theme)
        var ids = themeIDs
        // A theme that is chosen and no longer in the folder stays in the list, so the picker shows what is in use.
        if !ids.contains(selected) { ids.append(selected) }
        return AppearanceSettingsState(
            themes: ids.map { SettingsChoice(id: $0, title: $0 == ThemeStore.defaultID ? SettingsCopy.defaultTheme : $0) },
            selectedTheme: selected,
            modes: AppearanceMode.allCases.map { SettingsChoice(id: $0.rawValue, title: SettingsCopy.mode($0)) },
            selectedMode: settings.value(for: AppearanceSettings.mode).rawValue,
            themeError: dependencies.themeModel.errors.first.map { String(describing: $0) }
        )
    }

    /// Uses the theme at once and remembers it for the next launch. The windows follow the theme store, so nothing else
    /// has to be told.
    public func selectTheme(_ id: String) {
        settings.set(id, for: AppearanceSettings.theme)
        changed()
        let themes = dependencies.themes
        themeSelection = Task { await themes.select(id) }
    }

    /// Applies the choice of light, dark, or the system's to every window at once and remembers it.
    public func setAppearance(_ id: String) {
        guard let mode = AppearanceMode(rawValue: id) else { return }
        settings.set(mode, for: AppearanceSettings.mode)
        dependencies.themeModel.appearance = mode.override
        changed()
    }
}

extension AppearanceMode {
    /// The design system's name for the choice.
    public var override: AppearanceOverride {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }
}
