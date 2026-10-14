// The contract between the settings screen and the code that drives it. The screen draws these values and calls the
// intents; it knows nothing of the core, so every choice has an id and a title of its own here and the view model in
// `SusurroFeatures` maps them. Every text is ready to show.

/// One choice in a list the user picks from: a language, a tone, a theme.
public nonisolated struct SettingsChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// The tabs of the settings window.
public nonisolated enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case general, providers, hotkey, style, dictionary, appearance

    public var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .hotkey: "Hotkey"
        case .style: "Style"
        case .dictionary: "Dictionary"
        case .appearance: "Appearance"
        }
    }
}

// MARK: General

public nonisolated struct GeneralSettingsState: Equatable, Sendable {
    /// Fast with automatic detection, or one language that is always asked for.
    public let languages: [SettingsChoice]
    public let selectedLanguage: String
    public let appContextEnabled: Bool
    public let ocrEnabled: Bool
    public let cleanupEnabled: Bool
    public let overlayEdges: [SettingsChoice]
    public let selectedEdge: String
    public let overlayVariants: [SettingsChoice]
    public let selectedVariant: String
    /// Why the stored overlay variant is not the one in use, or nil when it is.
    public let variantError: String?

    public init(
        languages: [SettingsChoice], selectedLanguage: String, appContextEnabled: Bool, ocrEnabled: Bool,
        cleanupEnabled: Bool, overlayEdges: [SettingsChoice], selectedEdge: String,
        overlayVariants: [SettingsChoice], selectedVariant: String, variantError: String?
    ) {
        self.languages = languages
        self.selectedLanguage = selectedLanguage
        self.appContextEnabled = appContextEnabled
        self.ocrEnabled = ocrEnabled
        self.cleanupEnabled = cleanupEnabled
        self.overlayEdges = overlayEdges
        self.selectedEdge = selectedEdge
        self.overlayVariants = overlayVariants
        self.selectedVariant = selectedVariant
        self.variantError = variantError
    }
}

// MARK: Providers

/// How a provider stands, in words and in a tint.
public nonisolated struct ProviderStatusState: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        case ready, pending, warning, error
    }

    public let level: Level
    public let text: String

    public init(level: Level, text: String) {
        self.level = level
        self.text = text
    }
}

/// A value the user types for a provider: an endpoint, a path, a model.
public nonisolated struct ProviderFieldState: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let placeholder: String
    /// What is wrong with the value, or nil when it is usable.
    public let error: String?
    /// The values to pick from, when the field is a choice and not free text. `value` is the id of the one picked.
    public let choices: [SettingsChoice]

    public init(
        id: String, label: String, value: String, placeholder: String = "", error: String? = nil,
        choices: [SettingsChoice] = []
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.error = error
        self.choices = choices
    }
}

/// Whether a cloud provider's key is in the user's key store. The key itself never reaches the screen.
public nonisolated struct ProviderKeyState: Equatable, Sendable {
    public let isPresent: Bool
    /// Where to put the key when it is missing, or what is present when it is there.
    public let note: String

    public init(isPresent: Bool, note: String) {
        self.isPresent = isPresent
        self.note = note
    }
}

public nonisolated struct ProviderRowState: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Where the audio or the text goes: this Mac or a cloud service.
    public let locality: String
    public let isCloud: Bool
    public let isSelected: Bool
    public let status: ProviderStatusState
    /// The switch of a provider that has to be turned on first, or nil for one that is always on.
    public let isEnabled: Bool?
    public let key: ProviderKeyState?
    public let fields: [ProviderFieldState]

    public init(
        id: String, title: String, locality: String, isCloud: Bool, isSelected: Bool, status: ProviderStatusState,
        isEnabled: Bool?, key: ProviderKeyState?, fields: [ProviderFieldState]
    ) {
        self.id = id
        self.title = title
        self.locality = locality
        self.isCloud = isCloud
        self.isSelected = isSelected
        self.status = status
        self.isEnabled = isEnabled
        self.key = key
        self.fields = fields
    }
}

public nonisolated struct ProvidersSettingsState: Equatable, Sendable {
    public let speech: [ProviderRowState]
    public let cleanup: [ProviderRowState]

    public init(speech: [ProviderRowState], cleanup: [ProviderRowState]) {
        self.speech = speech
        self.cleanup = cleanup
    }
}

// MARK: Hotkey

public nonisolated struct HotkeyWarning: Equatable, Sendable {
    public let message: String
    /// The title of the button that fixes it, or nil when the user has to do it elsewhere.
    public let actionTitle: String?

    public init(message: String, actionTitle: String?) {
        self.message = message
        self.actionTitle = actionTitle
    }
}

public nonisolated struct HotkeySettingsState: Equatable, Sendable {
    /// The keys of the shortcut, one cap each, such as `⌃`, `⌥`, `D`.
    public let shortcut: [String]
    public let isModifierOnly: Bool
    /// The Input Monitoring problem of a modifier-only hotkey, or nil.
    public let permissionWarning: HotkeyWarning?
    /// A warning that Secure Event Input is on, which stops some hotkeys from being heard, or nil.
    public let secureInputWarning: String?

    public init(
        shortcut: [String], isModifierOnly: Bool, permissionWarning: HotkeyWarning?, secureInputWarning: String?
    ) {
        self.shortcut = shortcut
        self.isModifierOnly = isModifierOnly
        self.permissionWarning = permissionWarning
        self.secureInputWarning = secureInputWarning
    }
}

// MARK: Style

public nonisolated struct StyleRowState: Equatable, Sendable, Identifiable {
    /// The id of the category.
    public let id: String
    public let title: String
    /// The id of the tone the category has now.
    public let toneID: String
    /// Whether the user changed the tone from the one the app ships with.
    public let isEdited: Bool

    public init(id: String, title: String, toneID: String, isEdited: Bool) {
        self.id = id
        self.title = title
        self.toneID = toneID
        self.isEdited = isEdited
    }
}

public nonisolated struct StyleOverrideRowState: Equatable, Sendable, Identifiable {
    public let id: String
    /// "App" or "Site".
    public let kind: String
    /// The bundle id or the host.
    public let identifier: String
    /// What the override changes, ready to show: `Category: Document, Tone: Casual`.
    public let summary: String

    public init(id: String, kind: String, identifier: String, summary: String) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.summary = summary
    }
}

public nonisolated struct StyleSettingsState: Equatable, Sendable {
    public let rows: [StyleRowState]
    public let toneChoices: [SettingsChoice]
    public let categoryChoices: [SettingsChoice]
    public let overrides: [StyleOverrideRowState]
    /// Why the last override was refused, or nil.
    public let overrideError: String?

    public init(
        rows: [StyleRowState], toneChoices: [SettingsChoice], categoryChoices: [SettingsChoice],
        overrides: [StyleOverrideRowState], overrideError: String?
    ) {
        self.rows = rows
        self.toneChoices = toneChoices
        self.categoryChoices = categoryChoices
        self.overrides = overrides
        self.overrideError = overrideError
    }
}

// MARK: Dictionary and appearance

public nonisolated struct DictionarySettingsState: Equatable, Sendable {
    public let terms: [String]
    /// Why the last change was refused, or nil.
    public let error: String?

    public init(terms: [String], error: String?) {
        self.terms = terms
        self.error = error
    }
}

public nonisolated struct AppearanceSettingsState: Equatable, Sendable {
    public let themes: [SettingsChoice]
    public let selectedTheme: String
    /// System, light, or dark.
    public let modes: [SettingsChoice]
    public let selectedMode: String
    /// What is wrong with the theme file in use, or nil.
    public let themeError: String?

    public init(
        themes: [SettingsChoice], selectedTheme: String, modes: [SettingsChoice], selectedMode: String,
        themeError: String?
    ) {
        self.themes = themes
        self.selectedTheme = selectedTheme
        self.modes = modes
        self.selectedMode = selectedMode
        self.themeError = themeError
    }
}

// MARK: The screen

/// Everything the settings screen shows.
public nonisolated struct SettingsViewState: Equatable, Sendable {
    public let general: GeneralSettingsState
    public let providers: ProvidersSettingsState
    public let hotkey: HotkeySettingsState
    public let style: StyleSettingsState
    public let dictionary: DictionarySettingsState
    public let appearance: AppearanceSettingsState

    public init(
        general: GeneralSettingsState, providers: ProvidersSettingsState, hotkey: HotkeySettingsState,
        style: StyleSettingsState, dictionary: DictionarySettingsState, appearance: AppearanceSettingsState
    ) {
        self.general = general
        self.providers = providers
        self.hotkey = hotkey
        self.style = style
        self.dictionary = dictionary
        self.appearance = appearance
    }
}

/// What the settings screen needs from the code behind it. Every intent that changes a setting is applied at once and
/// shows in `state`.
@MainActor
public protocol SettingsViewModeling: AnyObject {
    var state: SettingsViewState { get }

    // General
    func setLanguage(_ id: String)
    func setAppContext(_ isOn: Bool)
    func setOCR(_ isOn: Bool)
    func setCleanup(_ isOn: Bool)
    func setOverlayEdge(_ id: String)
    func setOverlayVariant(_ id: String)

    // Providers
    func selectProvider(_ id: String)
    func setProviderEnabled(_ id: String, isOn: Bool)
    func setProviderField(_ id: String, field: String, value: String)

    // Hotkey
    /// Asks the system for Input Monitoring, which a modifier-only hotkey needs.
    func requestInputMonitoring() async

    // Style
    func setTone(category: String, tone: String)
    /// Adds or replaces the override of an app (`isSite` false) or a site. An empty category or tone leaves it alone.
    func addOverride(identifier: String, isSite: Bool, category: String?, tone: String?)
    func removeOverride(_ id: String)

    // Dictionary
    func addTerm(_ term: String)
    func editTerm(_ old: String, to new: String)
    func removeTerm(_ term: String)

    // Appearance
    func selectTheme(_ id: String)
    func setAppearance(_ id: String)

    /// Reads what can change without the screen's help (permission, Secure Event Input, readiness, the keys).
    func refresh() async
}
