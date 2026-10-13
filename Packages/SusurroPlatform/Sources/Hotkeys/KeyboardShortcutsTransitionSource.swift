import KeyboardShortcuts

/// The live transition source: Control+Option+D through KeyboardShortcuts (Carbon), which needs no permission.
struct KeyboardShortcutsTransitionSource: KeyTransitionSource {
    @MainActor
    func transitions() -> any AsyncSequence<KeyTransition, Never> {
        let name = KeyboardShortcuts.Name.holdToTalk
        // The combo is fixed until it becomes configurable, so a value stored by an earlier run never overrides it.
        KeyboardShortcuts.setShortcut(DefaultHotkey.holdToTalk, for: name)
        return KeyboardShortcuts.events(for: name).map { $0 == .keyDown ? KeyTransition.down : .up }
    }
}
