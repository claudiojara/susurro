import Domain

/// The hotkey as the settings show it.
public struct HotkeyDescription: Equatable, Sendable {
    /// The keys of the shortcut, one cap each, such as `⌃`, `⌥`, `D`.
    public let keys: [String]
    /// The shortcut is made of modifier keys only, or is the fn key, which needs Input Monitoring.
    public let isModifierOnly: Bool

    public init(keys: [String], isModifierOnly: Bool) {
        self.keys = keys
        self.isModifierOnly = isModifierOnly
    }
}

/// An overlay variant the user can pick.
public struct OverlayVariantOption: Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// The id of the variant that is used when the stored one is unknown.
    public static let defaultID = "default"
}

/// Chooses the theme in use. The theme store is the live one.
public protocol ThemeSelecting: Sendable {
    /// The id of every theme: the bundled one first, then the files of the themes folder.
    func themeIDs() async -> [String]
    /// Uses another theme.
    func select(_ id: String) async
}

/// What the settings view model needs from the rest of the app, as narrow ports, so that it can run on fakes.
public struct SettingsDependencies {
    public var settings: any SettingsStore
    /// Whether the account has a key in the key store. The key itself is never read here.
    public var hasKey: @Sendable (SecretAccount) -> Bool
    public var permissions: any PermissionsChecker
    public var hotkey: @MainActor () -> HotkeyDescription
    /// Whether Secure Event Input is on right now.
    public var secureInputActive: @Sendable () -> Bool
    /// The overlay variants that exist. The one with `OverlayVariantOption.defaultID` must be among them.
    public var overlayVariants: [OverlayVariantOption]
    public var style: any StylePreferencesStore
    public var dictionary: any DictionaryTermStore
    /// How a local speech provider stands: whether its model or its server is there.
    public var speechReadiness: @Sendable (String) async -> RecognizerReadiness
    /// Whether Apple's on-device cleanup model is available on this Mac.
    public var appleIntelligenceAvailable: @Sendable () async -> Bool
    /// Why a path cannot be run, or nil when it can.
    public var executableProblem: @Sendable (String) -> ExecutablePath.Problem?
    public var themes: any ThemeSelecting
    public var themeModel: ThemeModel
    /// Paces the reads of the permission and of Secure Event Input. Tests pass a `ManualClock`.
    public var clock: any Clock<Duration>

    public init(
        settings: any SettingsStore,
        hasKey: @escaping @Sendable (SecretAccount) -> Bool,
        permissions: any PermissionsChecker,
        hotkey: @escaping @MainActor () -> HotkeyDescription,
        secureInputActive: @escaping @Sendable () -> Bool,
        overlayVariants: [OverlayVariantOption],
        style: any StylePreferencesStore,
        dictionary: any DictionaryTermStore,
        speechReadiness: @escaping @Sendable (String) async -> RecognizerReadiness,
        appleIntelligenceAvailable: @escaping @Sendable () async -> Bool,
        executableProblem: @escaping @Sendable (String) -> ExecutablePath.Problem? = { ExecutablePath.validate($0) },
        themes: any ThemeSelecting,
        themeModel: ThemeModel,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.clock = clock
        self.settings = settings
        self.hasKey = hasKey
        self.permissions = permissions
        self.hotkey = hotkey
        self.secureInputActive = secureInputActive
        self.overlayVariants = overlayVariants
        self.style = style
        self.dictionary = dictionary
        self.speechReadiness = speechReadiness
        self.appleIntelligenceAvailable = appleIntelligenceAvailable
        self.executableProblem = executableProblem
        self.themes = themes
        self.themeModel = themeModel
    }
}
