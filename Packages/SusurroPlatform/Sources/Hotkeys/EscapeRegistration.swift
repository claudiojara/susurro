import KeyboardShortcuts
import Synchronization

/// Where Esc is registered with the system. Esc is registered only while a dictation is in flight, because a registered
/// Esc is taken from the app in front, which would break Esc everywhere else. The live one wraps KeyboardShortcuts;
/// tests count the calls.
protocol EscapeRegistration: Sendable {
    /// Starts taking Esc. `onEscape` runs each time it is pressed.
    func register(_ onEscape: @escaping @Sendable () -> Void)
    /// Gives Esc back to the app in front.
    func unregister()
}

/// The live registration: a Carbon hotkey for Esc, held for as long as a task reads its events.
final class KeyboardShortcutsEscapeRegistration: EscapeRegistration {
    private let listening = Mutex<Task<Void, Never>?>(nil)

    func register(_ onEscape: @escaping @Sendable () -> Void) {
        let task = Task { @MainActor in
            // The system registers the key as the stream is made and releases it when the stream is no longer read.
            for await event in KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape))
            where event == .keyDown {
                onEscape()
            }
        }
        listening.withLock { current in
            current?.cancel()
            current = task
        }
    }

    func unregister() {
        listening.withLock { current in
            current?.cancel()
            current = nil
        }
    }
}
