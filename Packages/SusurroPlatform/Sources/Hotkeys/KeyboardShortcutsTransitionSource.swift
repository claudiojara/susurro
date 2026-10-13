import KeyboardShortcuts

/// The live transition source: Control+Option+D through KeyboardShortcuts (Carbon), which needs no permission.
struct KeyboardShortcutsTransitionSource: KeyTransitionSource {
    func transitions() -> AsyncStream<KeyTransition> {
        let (transitions, continuation) = AsyncStream.makeStream(of: KeyTransition.self)
        // KeyboardShortcuts is main-actor isolated, so the registration is made there.
        let listening = Task { @MainActor in
            for await event in KeyboardShortcuts.events(for: DefaultHotkey.holdToTalk) {
                continuation.yield(event == .keyDown ? .down : .up)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in listening.cancel() }
        return transitions
    }
}
