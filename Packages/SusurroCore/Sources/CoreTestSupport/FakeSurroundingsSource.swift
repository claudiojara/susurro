import Domain

/// A surroundings source with a fixed answer.
public struct FakeSurroundingsSource: SurroundingsSource {
    private let answer: DictationSurroundings

    public init(_ answer: DictationSurroundings = .unknown) {
        self.answer = answer
    }

    public func surroundings() async -> DictationSurroundings { answer }
}
