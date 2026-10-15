// What the settings views can ask for, as closures, so that every view is a pure function of its state and its actions.
// The container builds them from the view model, and a preview or a snapshot passes `.none`.

public struct GeneralActions {
    public var language: (String) -> Void
    public var appContext: (Bool) -> Void
    public var ocr: (Bool) -> Void
    public var cleanup: (Bool) -> Void
    public var edge: (String) -> Void
    public var variant: (String) -> Void
    public var interfaceLanguage: (String) -> Void

    public static let none = GeneralActions(
        language: { _ in }, appContext: { _ in }, ocr: { _ in }, cleanup: { _ in }, edge: { _ in }, variant: { _ in },
        interfaceLanguage: { _ in })
}

public struct ProvidersActions {
    public var select: (String) -> Void
    public var setEnabled: (String, Bool) -> Void
    /// Provider id, field id, new value.
    public var setField: (String, String, String) -> Void

    public static let none = ProvidersActions(select: { _ in }, setEnabled: { _, _ in }, setField: { _, _, _ in })
}

public struct HotkeyActions {
    public var requestInputMonitoring: () -> Void

    public static let none = HotkeyActions(requestInputMonitoring: {})
}

public struct StyleActions {
    public var setTone: (_ category: String, _ tone: String) -> Void
    public var addOverride: (_ identifier: String, _ isSite: Bool, _ category: String?, _ tone: String?) -> Void
    public var removeOverride: (String) -> Void

    public static let none = StyleActions(
        setTone: { _, _ in }, addOverride: { _, _, _, _ in }, removeOverride: { _ in })
}

public struct DictionaryActions {
    public var add: (String) -> Void
    public var edit: (_ old: String, _ new: String) -> Void
    public var remove: (String) -> Void

    public static let none = DictionaryActions(add: { _ in }, edit: { _, _ in }, remove: { _ in })
}

public struct AppearanceActions {
    public var theme: (String) -> Void
    public var mode: (String) -> Void

    public static let none = AppearanceActions(theme: { _ in }, mode: { _ in })
}

/// Every action of the settings screen.
public struct SettingsActions {
    public var general: GeneralActions
    public var providers: ProvidersActions
    public var hotkey: HotkeyActions
    public var style: StyleActions
    public var dictionary: DictionaryActions
    public var appearance: AppearanceActions
    public var audio: AudioActions

    public static let none = SettingsActions(
        general: .none, providers: .none, hotkey: .none, style: .none, dictionary: .none, appearance: .none)

    /// The actions that call the intents of a view model.
    @MainActor
    public init(model: any SettingsViewModeling) {
        general = GeneralActions(
            language: { model.setLanguage($0) }, appContext: { model.setAppContext($0) }, ocr: { model.setOCR($0) },
            cleanup: { model.setCleanup($0) }, edge: { model.setOverlayEdge($0) },
            variant: { model.setOverlayVariant($0) }, interfaceLanguage: { model.setInterfaceLanguage($0) })
        providers = ProvidersActions(
            select: { model.selectProvider($0) }, setEnabled: { model.setProviderEnabled($0, isOn: $1) },
            setField: { model.setProviderField($0, field: $1, value: $2) })
        hotkey = HotkeyActions(requestInputMonitoring: { Task { await model.requestInputMonitoring() } })
        style = StyleActions(
            setTone: { model.setTone(category: $0, tone: $1) },
            addOverride: { model.addOverride(identifier: $0, isSite: $1, category: $2, tone: $3) },
            removeOverride: { model.removeOverride($0) })
        dictionary = DictionaryActions(
            add: { model.addTerm($0) }, edit: { model.editTerm($0, to: $1) }, remove: { model.removeTerm($0) })
        appearance = AppearanceActions(theme: { model.selectTheme($0) }, mode: { model.setAppearance($0) })
        audio = AudioActions(microphone: { model.selectMicrophone($0) }, pauseMedia: { model.setPauseMedia($0) })
    }

    public init(
        general: GeneralActions, providers: ProvidersActions, hotkey: HotkeyActions, style: StyleActions,
        dictionary: DictionaryActions, appearance: AppearanceActions, audio: AudioActions = .none
    ) {
        self.general = general
        self.providers = providers
        self.hotkey = hotkey
        self.style = style
        self.dictionary = dictionary
        self.appearance = appearance
        self.audio = audio
    }
}
