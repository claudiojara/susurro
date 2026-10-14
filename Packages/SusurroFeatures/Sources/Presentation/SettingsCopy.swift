import Domain
import SusurroUI

/// The words of the settings that the view model puts in the view state, in one place.
enum SettingsCopy {
    // MARK: General

    static let fastLanguage = "Fast (auto language)"
    static let alwaysSpanish = "Always Spanish"
    static let top = "Top"
    static let bottom = "Bottom"

    static func variantUnavailable(_ id: String) -> String {
        "The overlay style \"\(id)\" is not available, so the default one is used."
    }

    static func language(_ language: SpeechLanguage) -> String {
        switch language {
        case .auto: fastLanguage
        case .spanish: alwaysSpanish
        }
    }

    static func edge(_ edge: OverlayEdge) -> String {
        switch edge {
        case .top: top
        case .bottom: bottom
        }
    }

    // MARK: Providers

    static let thisMac = "On this Mac"
    static let cloud = "Cloud service"
    static let checking = "Checking..."
    static let off = "Off. Turn it on to use it."

    static func keyMissing(_ account: SecretAccount) -> String {
        "Add the key to your Keychain: service app.tuminuta, account \(account.rawValue)."
    }

    static func keyPresent(_ account: SecretAccount) -> String {
        "A key is in your Keychain (app.tuminuta, \(account.rawValue))."
    }

    static func needsKey(_ account: SecretAccount) -> String {
        "Add a key to your Keychain (app.tuminuta, \(account.rawValue))."
    }

    static func sentTo(_ service: String, what: String) -> String {
        "Ready. The \(what) is sent to \(service)."
    }

    static func loading(_ progress: Double) -> String {
        "Loading the model, \(Int((progress * 100).rounded())) %."
    }

    static let ready = "Ready"
    static let modelNotInstalled = "The model is not installed."
    static let notReachable = "Not reachable. Start your Whisper server or check the path."
    static let appleUnavailable = "Apple Intelligence is not available on this Mac."
    static let localWhisperAddressError = "The address must be on this Mac: localhost or 127.0.0.1."
    static let baseURLError = "Use an https address, or http on this Mac."

    static func executableProblem(_ problem: ExecutablePath.Problem) -> String {
        switch problem {
        case .empty: "Enter the full path of your Whisper command."
        case .notAbsolute: "The path must start with a slash."
        case .missing: "There is no file at that path."
        case .notExecutable: "That file cannot be run."
        }
    }

    // MARK: Hotkey

    static let inputMonitoringWarning =
        "This hotkey is made only of modifier keys, so it stays off until Input Monitoring is allowed."
    static let allowInputMonitoring = "Allow Input Monitoring"
    static let secureInputWarning =
        "Secure Event Input is on, so keyed shortcuts may not respond until it ends. A password field or another app has turned it on."

    // MARK: Style

    static let noOverrideTarget = "Enter a bundle id or a website."
    static let noOverrideChange = "Choose a category, a tone, or both."

    static func category(_ category: AppCategory) -> String {
        switch category {
        case .email: "Email"
        case .workChat: "Work chat"
        case .personalMessaging: "Personal messaging"
        case .document: "Document"
        case .terminal: "Terminal"
        case .aiChat: "AI chat"
        case .other: "Other"
        }
    }

    static func tone(_ tone: Tone) -> String {
        switch tone {
        case .formal: "Formal"
        case .neutral: "Neutral"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .verbatim: "Verbatim"
        }
    }

    static func overrideSummary(category: AppCategory?, tone: Tone?) -> String {
        var parts: [String] = []
        if let category { parts.append("Category: \(Self.category(category))") }
        if let tone { parts.append("Tone: \(Self.tone(tone))") }
        return parts.joined(separator: ", ")
    }

    // MARK: Dictionary and appearance

    static let emptyTerm = "Enter a word or a name."
    static let duplicateTerm = "That term is already in the dictionary."

    static func termTooLong(_ limit: Int) -> String {
        "A term can have at most \(limit) characters."
    }

    static func mode(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: "Follow the system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static let defaultTheme = "Default"
}
