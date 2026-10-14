/// A key event heard while the user records a hotkey, reduced to what the recording needs.
public enum HotkeyCaptureInput: Sendable, Equatable {
    /// A key that is not a modifier went down, with the modifiers held at that moment. `code` is the virtual key code.
    case key(code: Int, modifiers: HotkeyModifiers)
    /// The modifier keys that are down changed to these.
    case modifiers(HotkeyModifiers)
}

/// Where the keys of a recording come from: the live one listens to the keyboard while the settings window is key and
/// keeps the keys from the rest of the app; a test scripts them.
public protocol HotkeyCaptureSource: Sendable {
    /// Starts listening and returns the inputs. The listening stops when the stream is no longer read, and the stream ends
    /// by itself when the window stops being the one that gets the keys.
    func inputs() -> AsyncStream<HotkeyCaptureInput>
}

/// The key codes a hotkey cares about. They are the virtual key codes of the keyboard (Carbon's `kVK_` numbers).
public enum HotkeyKeyCodes {
    public static let escape = 53

    /// F1 to F20.
    public static let functionKeys: Set<Int> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// The keys for which the system raises the fn flag by itself: the function keys, the arrows, and the editing keys
    /// (Help, Home, Page Up, Forward Delete, End, Page Down). The flag says nothing about whether fn was held.
    static let raiseFunctionFlag: Set<Int> = functionKeys.union([
        123, 124, 125, 126, 114, 115, 116, 117, 119, 121,
    ])
}

extension HotkeyModifiers {
    /// The key caps of the modifiers in the order of the macOS menus, with fn first: `fn`, `⌃`, `⌥`, `⇧`, `⌘`.
    public var caps: [String] {
        let all: [(HotkeyModifiers, String)] = [
            (.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return all.filter { contains($0.0) }.map { $0.1 }
    }

    var count: Int { rawValue.nonzeroBitCount }
}

/// Turns the keys of a recording into a hotkey. A key with modifiers is a keyed candidate the moment it goes down.
/// Modifier keys alone are a candidate when the last of them is let go, and are the biggest set that was held together:
/// fn alone, or a chord such as Control and Option. Escape alone cancels. A pure value, so the rules are tested without a
/// keyboard.
public struct HotkeyCapture: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Nothing to decide yet.
        case none
        /// The hotkey the user pressed. Whether it is allowed is for `HotkeyValidation`.
        case candidate(HotkeyConfiguration)
        /// The user pressed Escape to give up.
        case cancel
    }

    /// The modifier keys that are down now, which a view shows while the user records.
    public private(set) var held: HotkeyModifiers = []
    private var biggest: HotkeyModifiers = []
    private var keyWasPressed = false

    public init() {}

    public mutating func handle(_ input: HotkeyCaptureInput) -> Outcome {
        switch input {
        case .key(let code, let modifiers):
            if code == HotkeyKeyCodes.escape && modifiers.isEmpty { return .cancel }
            keyWasPressed = true
            held = modifiers
            let kept = HotkeyKeyCodes.raiseFunctionFlag.contains(code) ? modifiers.subtracting(.function) : modifiers
            return .candidate(HotkeyConfiguration(kind: .keyed, combo: HotkeyCombo(keyCode: code, modifiers: kept)))
        case .modifiers(let modifiers):
            held = modifiers
            if modifiers.count > biggest.count { biggest = modifiers }
            guard modifiers.isEmpty else { return .none }
            defer {
                biggest = []
                keyWasPressed = false
            }
            guard !keyWasPressed, !biggest.isEmpty else { return .none }
            return .candidate(
                HotkeyConfiguration(kind: .modifierOnly, combo: HotkeyCombo(keyCode: nil, modifiers: biggest)))
        }
    }
}
