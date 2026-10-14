// The style vocabulary of the dictation: what kind of app the text goes to, and how formal it should read. The names and
// values follow the style-resolution spec. The resolver that decides them for an app lives with the style slice; the
// settings read and edit these values.

/// What kind of app or site the text goes to.
public enum AppCategory: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case email
    case workChat = "work_chat"
    case personalMessaging = "personal_messaging"
    case document
    case terminal
    case aiChat = "ai_chat"
    case other

    /// The tone a category has until the user changes it.
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

/// How formal the cleaned text should read. Verbatim means no cleanup at all.
public enum Tone: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case formal
    case neutral
    case casual
    case veryCasual
    case verbatim
}

/// The category and the tone a dictation is cleaned with.
public struct StyleProfile: Sendable, Equatable, Hashable, Codable {
    public let category: AppCategory
    public let tone: Tone

    public init(category: AppCategory, tone: Tone) {
        self.category = category
        self.tone = tone
    }
}

/// What a user override applies to: one app by its bundle id, or one site by its host.
public enum StyleTarget: Sendable, Equatable, Hashable, Codable {
    case app(bundleID: String)
    case site(host: String)

    /// The bundle id or the host, whichever it is.
    public var identifier: String {
        switch self {
        case .app(let bundleID): bundleID
        case .site(let host): host
        }
    }
}

/// The user's choice of category, tone, or both for an app or a site. An override with neither changes nothing and is
/// not kept.
public struct StyleOverride: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let target: StyleTarget
    public let category: AppCategory?
    public let tone: Tone?

    public var id: StyleTarget { target }

    public init(target: StyleTarget, category: AppCategory? = nil, tone: Tone? = nil) {
        self.target = target
        self.category = category
        self.tone = tone
    }
}
