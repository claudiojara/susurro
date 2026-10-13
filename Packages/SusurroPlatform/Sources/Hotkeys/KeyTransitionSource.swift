/// Where raw press and release transitions of the hotkey come from. The live one wraps KeyboardShortcuts; tests script
/// their own.
protocol KeyTransitionSource: Sendable {
    /// Starts listening. KeyboardShortcuts is main-thread only, so subscribing happens on the main actor. The listener
    /// stops when the returned sequence is no longer iterated.
    @MainActor func transitions() -> any AsyncSequence<KeyTransition, Never>
}
