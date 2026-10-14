import Domain

/// Where raw press and release transitions of the hotkey come from. The live one wraps KeyboardShortcuts for a keyed
/// hotkey and a listen-only monitor of the modifier flags for a modifier-only one; tests script their own.
protocol KeyTransitionSource: Sendable {
    /// Starts listening for the hotkey of `configuration` and returns the transitions. The listener stops when the stream
    /// is no longer read.
    func transitions(for configuration: HotkeyConfiguration) -> AsyncStream<KeyTransition>
}
