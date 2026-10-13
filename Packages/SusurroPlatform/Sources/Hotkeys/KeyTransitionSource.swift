/// Where raw press and release transitions of the hotkey come from. The live one wraps KeyboardShortcuts; tests script
/// their own.
protocol KeyTransitionSource: Sendable {
    /// Starts listening and returns the transitions. The listener stops when the stream is no longer read.
    func transitions() -> AsyncStream<KeyTransition>
}
