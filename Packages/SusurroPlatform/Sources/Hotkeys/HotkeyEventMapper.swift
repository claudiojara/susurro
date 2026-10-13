import Domain

/// A raw press or release of the hotkey, before any filtering.
enum KeyTransition: Sendable, Equatable {
    case down
    case up
}

/// Turns raw key transitions into `HotkeyEvent`s. The system may repeat a down while the key is held, or report an up
/// for a press that began before listening, so only a down that starts a press and the up that ends it pass through.
struct HotkeyEventMapper: Sendable {
    private var isHeld = false

    init() {}

    /// Returns the event for `transition`, or nil when it repeats or has no matching press.
    mutating func map(_ transition: KeyTransition, at time: Duration) -> HotkeyEvent? {
        switch transition {
        case .down:
            guard !isHeld else { return nil }
            isHeld = true
            return .down(at: time)
        case .up:
            guard isHeld else { return nil }
            isHeld = false
            return .up(at: time)
        }
    }
}
