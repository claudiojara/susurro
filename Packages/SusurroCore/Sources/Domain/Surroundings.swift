/// What the pipeline knows about the place a dictation goes to, once the recording ends: the style it is written in, the
/// terms the recognizer and the cleaner should get right, and the text around the cursor.
public struct DictationSurroundings: Sendable, Equatable {
    public let style: StyleProfile
    /// The vocabulary: the user's dictionary first, then the names found around the cursor and on screen.
    public let vocabulary: [String]
    /// The text around the cursor, or nil when it could not be read.
    public let cursor: CursorContext?

    public init(style: StyleProfile, vocabulary: [String] = [], cursor: CursorContext? = nil) {
        self.style = style
        self.vocabulary = vocabulary
        self.cursor = cursor
    }

    /// Nothing is known: the neutral style of an unknown app, no vocabulary, and no text around the cursor.
    public static let unknown = DictationSurroundings(style: StyleProfile(category: .other, tone: .neutral))
}

/// Where the pipeline asks for the surroundings of a dictation. The context-capture and vocabulary code implements it;
/// an implementation answers within its own deadline, and answers `.unknown` when it has nothing.
public protocol SurroundingsSource: Sendable {
    func surroundings() async -> DictationSurroundings
}
