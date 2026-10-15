import Domain
import SusurroUI

/// The words of the settings that the view model puts in the view state, in one place. The sentences are in the string
/// catalog of the module (`Localizable.xcstrings`), under the keys written here.
enum SettingsCopy {
    /// The title of the settings window.
    static var windowTitle: String { L10n.string("settings.windowTitle", "Susurro Settings") }

    // MARK: General

    static var fastLanguage: String { L10n.string("settings.language.fast", "Fast (auto language)") }
    static var alwaysSpanish: String { L10n.string("settings.language.spanish", "Always Spanish") }
    static var top: String { L10n.string("settings.edge.top", "Top") }
    static var bottom: String { L10n.string("settings.edge.bottom", "Bottom") }

    static func variantUnavailable(_ id: String) -> String {
        L10n.string(
            "settings.variant.unavailable", "The overlay style \"\(id)\" is not available, so the default one is used.")
    }

    /// The name of an overlay style of the app, or nil for one it does not know.
    static func overlayStyle(_ id: String) -> String? {
        switch id {
        case OverlayVariantOption.defaultID: defaultTheme
        case "minimal": L10n.string("settings.overlayStyle.minimal", "Minimal")
        case "liveText": L10n.string("settings.overlayStyle.liveText", "Live text")
        default: nil
        }
    }

    static func language(_ mode: SpeechLanguageMode) -> String {
        switch mode {
        case .fast: fastLanguage
        case .guaranteedSpanish: alwaysSpanish
        }
    }

    static func edge(_ edge: OverlayEdge) -> String {
        switch edge {
        case .top: top
        case .bottom: bottom
        }
    }

    /// The name of a choice of the interface language. A language is named in itself, so it can be found in any of them.
    static func interfaceLanguage(_ language: InterfaceLanguage) -> String {
        switch language {
        case .system: L10n.string("settings.interfaceLanguage.system", "System")
        case .english: "English"
        case .spanish: "Español"
        }
    }

    // MARK: Providers

    static var thisMac: String { L10n.string("settings.provider.thisMac", "On this Mac") }
    static var cloud: String { L10n.string("settings.provider.cloud", "Cloud service") }
    static var checking: String { L10n.string("settings.provider.checking", "Checking...") }
    static var off: String { L10n.string("settings.provider.off", "Off. Turn it on to use it.") }

    static func keyMissing(_ account: SecretAccount) -> String {
        L10n.string(
            "settings.provider.keyMissing",
            "Add the key to your Keychain: service app.tuminuta, account \(account.rawValue).")
    }

    static func keyPresent(_ account: SecretAccount) -> String {
        L10n.string("settings.provider.keyPresent", "A key is in your Keychain (app.tuminuta, \(account.rawValue)).")
    }

    static func needsKey(_ account: SecretAccount) -> String {
        L10n.string("settings.provider.needsKey", "Add a key to your Keychain (app.tuminuta, \(account.rawValue)).")
    }

    /// What a cloud provider is sent: the audio, or the transcript. Each makes its own sentence, since a language can
    /// need other words around each.
    enum Payload { case audio, transcript }

    static func sentTo(_ service: String, what: Payload) -> String {
        switch what {
        case .audio: L10n.string("settings.provider.sentAudio", "Ready. The audio is sent to \(service).")
        case .transcript:
            L10n.string("settings.provider.sentTranscript", "Ready. The transcript is sent to \(service).")
        }
    }

    static func loading(_ progress: Double) -> String {
        L10n.string("settings.provider.loading", "Loading the model, \(Int((progress * 100).rounded())) %.")
    }

    static var ready: String { L10n.string("settings.provider.ready", "Ready") }
    static var modelNotInstalled: String {
        L10n.string("settings.provider.notInstalled", "The model is not installed.")
    }
    static var notReachable: String {
        L10n.string("settings.provider.notReachable", "Not reachable. Start your Whisper server or check the path.")
    }
    static var appleUnavailable: String {
        L10n.string("settings.provider.appleUnavailable", "Apple Intelligence is not available on this Mac.")
    }
    static var localWhisperAddressError: String {
        L10n.string("settings.provider.localAddress", "The address must be on this Mac: localhost or 127.0.0.1.")
    }
    static var baseURLError: String {
        L10n.string("settings.provider.baseURL", "Use an https address, or http on this Mac.")
    }

    static func executableProblem(_ problem: ExecutablePath.Problem) -> String {
        switch problem {
        case .empty: L10n.string("settings.executable.empty", "Enter the full path of your Whisper command.")
        case .notAbsolute: L10n.string("settings.executable.notAbsolute", "The path must start with a slash.")
        case .missing: L10n.string("settings.executable.missing", "There is no file at that path.")
        case .notExecutable: L10n.string("settings.executable.notExecutable", "That file cannot be run.")
        }
    }

    // MARK: Provider fields

    static var connection: String { L10n.string("settings.field.connection", "Connection") }
    static var serverOnThisMac: String { L10n.string("settings.field.connection.server", "Server on this Mac") }
    static var commandLineTool: String { L10n.string("settings.field.connection.cli", "Command line tool") }
    static var server: String { L10n.string("settings.field.server", "Server") }
    static var address: String { L10n.string("settings.field.address", "Address") }
    static var optionalModel: String { L10n.string("settings.field.optionalModel", "Model (optional)") }
    static var commandPath: String { L10n.string("settings.field.commandPath", "Command path") }
    static var model: String { L10n.string("settings.field.model", "Model") }
    static var baseURL: String { L10n.string("settings.field.baseURL", "Base URL") }

    // MARK: Hotkey

    static var inputMonitoringWarning: String {
        L10n.string(
            "settings.hotkey.inputMonitoringWarning",
            "This hotkey is made only of modifier keys, so it stays off until Input Monitoring is allowed.")
    }
    static var allowInputMonitoring: String {
        L10n.string("settings.hotkey.allowInputMonitoring", "Allow Input Monitoring")
    }
    static var secureInputWarning: String {
        L10n.string(
            "settings.hotkey.secureInput",
            "Secure Event Input is on, so keyed shortcuts may not respond until it ends. A password field or another app has turned it on."
        )
    }

    /// Why a shortcut that the user pressed is not accepted, with what to press instead.
    static func rejection(_ reason: HotkeyRejection) -> String {
        switch reason {
        case .needsStrongerModifiers:
            L10n.string(
                "settings.hotkey.rejection.stronger",
                "Press the key together with Control, or with Option and Command. Other combinations clash with typing or with the shortcuts of other apps."
            )
        case .escapeIsReserved:
            L10n.string(
                "settings.hotkey.rejection.escape",
                "Esc cancels a dictation, so it cannot also start one. Press another key.")
        case .functionNeedsToBeAlone:
            L10n.string(
                "settings.hotkey.rejection.function",
                "fn cannot be combined with a key. Press fn alone, or use another modifier.")
        case .takenBySystem:
            L10n.string(
                "settings.hotkey.rejection.system",
                "macOS already uses this shortcut. Press another one, or turn the system shortcut off in System Settings."
            )
        case .needsFunctionOrTwoModifiers:
            L10n.string(
                "settings.hotkey.rejection.twoModifiers",
                "One modifier key alone is pressed by accident too often. Press fn, or hold two or more modifier keys.")
        case .needsKey:
            L10n.string(
                "settings.hotkey.rejection.needsKey",
                "This shortcut is tapped, so it needs a key. Hold modifier keys and press a key.")
        case .sameAsDictation:
            L10n.string(
                "settings.hotkey.rejection.sameAsDictation",
                "The dictation hotkey already uses this shortcut. Press another one.")
        case .alreadyInUse:
            L10n.string(
                "settings.hotkey.rejection.inUse",
                "Another Susurro shortcut already uses these keys. Press another one.")
        case .overlapsAnotherHotkey:
            L10n.string(
                "settings.hotkey.rejection.overlaps",
                "These modifier keys are part of another Susurro shortcut, so pressing one would start the other. Press another one."
            )
        }
    }

    /// The button that takes the paste last dictation shortcut away.
    static var removeShortcut: String { L10n.string("settings.hotkey.removeShortcut", "Remove shortcut") }

    // MARK: Audio

    static var systemDefaultMicrophone: String { L10n.string("settings.microphone.systemDefault", "System default") }
    static var microphoneNotConnected: String { L10n.string("settings.microphone.notConnected", "Not connected") }
    static var microphoneMissing: String {
        L10n.string(
            "settings.microphone.missing",
            "The microphone you chose is not connected. The system default is used until it is back.")
    }

    // MARK: Style

    static var noOverrideTarget: String { L10n.string("settings.style.noTarget", "Enter a bundle id or a website.") }
    static var noOverrideChange: String {
        L10n.string("settings.style.noChange", "Choose a category, a tone, or both.")
    }
    static var appKind: String { L10n.string("settings.style.kind.app", "App") }
    static var siteKind: String { L10n.string("settings.style.kind.site", "Site") }

    static func category(_ category: AppCategory) -> String {
        switch category {
        case .email: L10n.string("settings.category.email", "Email")
        case .workChat: L10n.string("settings.category.workChat", "Work chat")
        case .personalMessaging: L10n.string("settings.category.personalMessaging", "Personal messaging")
        case .document: L10n.string("settings.category.document", "Document")
        case .terminal: L10n.string("settings.category.terminal", "Terminal")
        case .aiChat: L10n.string("settings.category.aiChat", "AI chat")
        case .other: L10n.string("settings.category.other", "Other")
        }
    }

    static func tone(_ tone: Tone) -> String {
        switch tone {
        case .formal: L10n.string("settings.tone.formal", "Formal")
        case .neutral: L10n.string("settings.tone.neutral", "Neutral")
        case .casual: L10n.string("settings.tone.casual", "Casual")
        case .veryCasual: L10n.string("settings.tone.veryCasual", "Very casual")
        case .verbatim: L10n.string("settings.tone.verbatim", "Verbatim")
        }
    }

    static func overrideSummary(category: AppCategory?, tone: Tone?) -> String {
        var parts: [String] = []
        if let category {
            parts.append(L10n.string("settings.style.summary.category", "Category: \(Self.category(category))"))
        }
        if let tone { parts.append(L10n.string("settings.style.summary.tone", "Tone: \(Self.tone(tone))")) }
        return parts.joined(separator: ", ")
    }

    // MARK: Dictionary and appearance

    static var emptyTerm: String { L10n.string("settings.dictionary.empty", "Enter a word or a name.") }
    static var duplicateTerm: String {
        L10n.string("settings.dictionary.duplicate", "That term is already in the dictionary.")
    }

    static func termTooLong(_ limit: Int) -> String {
        L10n.string("settings.dictionary.tooLong", "A term can have at most \(limit) characters.")
    }

    static func mode(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: L10n.string("settings.appearance.system", "Follow the system")
        case .light: L10n.string("settings.appearance.light", "Light")
        case .dark: L10n.string("settings.appearance.dark", "Dark")
        }
    }

    static var defaultTheme: String { L10n.string("settings.theme.default", "Default") }
}
