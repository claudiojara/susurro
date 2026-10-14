/// What kind of app the user is dictating into. The raw values are how a category is stored.
public enum AppCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case email
    case workChat = "work_chat"
    case personalMessaging = "personal_messaging"
    case document
    case terminal
    case aiChat = "ai_chat"
    case other

    /// The tone of a category until the user changes it.
    public var defaultTone: Tone {
        switch self {
        case .email: .formal
        case .workChat: .casual
        case .personalMessaging: .veryCasual
        case .document: .neutral
        case .terminal: .verbatim
        case .aiChat: .neutral
        case .other: .neutral
        }
    }
}

/// How the dictated text should read. The raw values are how a tone is stored.
public enum Tone: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case formal
    case neutral
    case casual
    case veryCasual
    case verbatim
}

/// Which rule decided a style.
public enum StyleSource: String, Sendable, Equatable, Codable {
    /// The user's override for the app or the site.
    case override
    /// The host of the page in a browser.
    case url
    /// The bundle ID of the app.
    case bundle
    /// Nothing matched, so the category is `other`.
    case `default`
}

/// The category and tone the dictated text is shaped for, and the rule that chose them.
public struct StyleProfile: Sendable, Equatable {
    public let category: AppCategory
    public let tone: Tone
    public let source: StyleSource

    public init(category: AppCategory, tone: Tone, source: StyleSource) {
        self.category = category
        self.tone = tone
        self.source = source
    }
}

/// What an override applies to: an app by bundle ID, or a site by host.
public enum StyleTarget: Sendable, Equatable, Hashable {
    case bundle(String)
    case host(String)
}

/// The user's choice for an app or a site: a category, a tone, or both. What is nil is decided by the other rules.
public struct StyleOverride: Sendable, Equatable {
    public var category: AppCategory?
    public var tone: Tone?

    public init(category: AppCategory? = nil, tone: Tone? = nil) {
        self.category = category
        self.tone = tone
    }

    /// An override that changes nothing.
    public var isEmpty: Bool { category == nil && tone == nil }
}

/// What the user changed about styles: the tone of a category, and the overrides for apps and sites.
public struct StyleSettings: Sendable, Equatable {
    /// The tone the user chose for a category. A category that is not here has its default tone.
    public var tones: [AppCategory: Tone]
    public var overrides: [StyleTarget: StyleOverride]

    public init(tones: [AppCategory: Tone] = [:], overrides: [StyleTarget: StyleOverride] = [:]) {
        self.tones = tones
        self.overrides = overrides
    }

    public static let `default` = StyleSettings()
}
