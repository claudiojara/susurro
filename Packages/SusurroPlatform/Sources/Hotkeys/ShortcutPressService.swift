import Domain

/// The presses of a keyed shortcut stored in the settings, such as the one that pastes the last dictation
/// (`PasteLastSettings.combo`). Nothing is listened to while the shortcut is unassigned, and a shortcut the user changes
/// is listened to at once. A press is the key going down; a down repeated while the key is held is not another press.
/// The registration ends when the stream is no longer read.
public final class ShortcutPressService: ShortcutPressSource {
    private let settings: any SettingsStore
    private let key: SettingKey<HotkeyCombo?>
    private let source: any KeyTransitionSource

    public convenience init(settings: any SettingsStore, key: SettingKey<HotkeyCombo?>) {
        self.init(settings: settings, key: key, source: KeyboardShortcutsTransitionSource())
    }

    init(settings: any SettingsStore, key: SettingKey<HotkeyCombo?>, source: any KeyTransitionSource) {
        self.settings = settings
        self.key = key
        self.source = source
    }

    public func presses() -> AsyncStream<Void> {
        let (presses, continuation) = AsyncStream.makeStream(of: Void.self)
        // The changes are subscribed to before the first read, so a change in between is not missed.
        let changes = settings.values(for: key)
        let initial = settings.value(for: key)
        let supervising = Task { [source] in
            var current: HotkeyCombo?
            var listening: Task<Void, Never>?
            defer { listening?.cancel() }
            func follow(_ combo: HotkeyCombo?) {
                guard combo != current else { return }
                current = combo
                listening?.cancel()
                listening = combo.map { Self.listen(to: $0, source: source, into: continuation) }
            }
            follow(initial)
            for await combo in changes { follow(combo) }
        }
        continuation.onTermination = { _ in supervising.cancel() }
        return presses
    }

    private static func listen(
        to combo: HotkeyCombo, source: any KeyTransitionSource, into continuation: AsyncStream<Void>.Continuation
    ) -> Task<Void, Never> {
        let transitions = source.transitions(for: HotkeyConfiguration(kind: .keyed, combo: combo))
        return Task {
            var isDown = false
            for await transition in transitions {
                switch transition {
                case .down where !isDown:
                    isDown = true
                    continuation.yield()
                case .up:
                    isDown = false
                default:
                    break
                }
            }
            // A source that ends ends the presses. A listener replaced by a new shortcut does not.
            if !Task.isCancelled { continuation.finish() }
        }
    }
}
