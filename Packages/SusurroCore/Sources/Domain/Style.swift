/// What kind of app the text goes to. It decides the default tone.
///
/// Provisional: the style-resolution track (6a.4) owns this file and adds the source and override types. The cleanup
/// code reads only `category` and `tone`.
public enum AppCategory: String, Sendable, Equatable, CaseIterable {
    case email
    case workChat = "work_chat"
    case personalMessaging = "personal_messaging"
    case document
    case terminal
    case aiChat = "ai_chat"
    case other
}

public enum Tone: String, Sendable, Equatable, CaseIterable {
    case formal
    case neutral
    case casual
    case veryCasual
    /// The transcript goes in as it was heard: cleanup is skipped.
    case verbatim
}

/// The category and tone a dictation is written in.
public struct StyleProfile: Sendable, Equatable {
    public let category: AppCategory
    public let tone: Tone

    public init(category: AppCategory, tone: Tone) {
        self.category = category
        self.tone = tone
    }
}
