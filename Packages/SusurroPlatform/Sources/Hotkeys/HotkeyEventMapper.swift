import Domain

/// A raw change of the hotkey, before any filtering.
enum KeyTransition: Sendable, Equatable {
    case down
    case up
    /// The modifier keys that are down changed. Only a modifier-only hotkey looks at these.
    case flags(HotkeyModifiers)
}

/// Turns raw key transitions into `HotkeyEvent`s. The system may repeat a down while the key is held, or report an up
/// for a press that began before listening, so only a down that starts a press and the up that ends it pass through.
///
/// A modifier-only hotkey is down while the modifier keys that are held are exactly its own. Anything else, such as one
/// more modifier pressed with it, or one of them let go, ends the press: the hotkey is a chord of modifiers, and a chord
/// that has grown is another chord.
struct HotkeyEventMapper: Sendable {
    private var isHeld = false
    private let modifierTarget: HotkeyModifiers?

    /// - Parameter modifierTarget: The modifiers of a modifier-only hotkey. Nil for a keyed one, which ignores flags.
    init(modifierTarget: HotkeyModifiers? = nil) {
        self.modifierTarget = modifierTarget
    }

    /// Returns the event for `transition`, or nil when it repeats or has no matching press.
    mutating func map(_ transition: KeyTransition, at time: Duration) -> HotkeyEvent? {
        switch transition {
        case .down:
            return press(at: time)
        case .up:
            return release(at: time)
        case .flags(let flags):
            guard let modifierTarget else { return nil }
            return flags == modifierTarget ? press(at: time) : release(at: time)
        }
    }

    private mutating func press(at time: Duration) -> HotkeyEvent? {
        guard !isHeld else { return nil }
        isHeld = true
        return .down(at: time)
    }

    private mutating func release(at time: Duration) -> HotkeyEvent? {
        guard isHeld else { return nil }
        isHeld = false
        return .up(at: time)
    }
}
