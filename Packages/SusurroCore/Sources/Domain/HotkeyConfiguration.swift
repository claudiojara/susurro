/// The modifier keys a hotkey is made of. The fn key counts as one, since a hotkey can be fn alone.
public struct HotkeyModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = HotkeyModifiers(rawValue: 1 << 0)
    public static let option = HotkeyModifiers(rawValue: 1 << 1)
    public static let shift = HotkeyModifiers(rawValue: 1 << 2)
    public static let command = HotkeyModifiers(rawValue: 1 << 3)
    public static let function = HotkeyModifiers(rawValue: 1 << 4)
}

/// What kind of key makes the hotkey, which decides what it needs from the system.
public enum HotkeyKind: String, Sendable, CaseIterable {
    /// A key with modifiers. It is registered with the system (Carbon), needs no permission, and works while Secure Event
    /// Input is on.
    case keyed
    /// Modifier keys alone, such as fn or Control+Option. They are read by listening to the modifier flags, which needs
    /// Input Monitoring, and they cannot be read while Secure Event Input is on.
    case modifierOnly
}

/// The keys of a hotkey. A keyed hotkey has a `keyCode`; a modifier-only one has none.
public struct HotkeyCombo: Codable, Sendable, Equatable {
    /// The virtual key code of the key (the Carbon `kVK_` number).
    public var keyCode: Int?
    public var modifiers: HotkeyModifiers

    public init(keyCode: Int?, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control+Option+D (`kVK_ANSI_D` is 2), the combination of the first usable build. See ADR 0005 for the check that it
    /// collides with no enabled macOS shortcut.
    public static let holdToTalk = HotkeyCombo(keyCode: 2, modifiers: [.control, .option])
}

/// The hotkey as the user configured it.
public struct HotkeyConfiguration: Sendable, Equatable {
    public var kind: HotkeyKind
    public var combo: HotkeyCombo

    public init(kind: HotkeyKind, combo: HotkeyCombo) {
        self.kind = kind
        self.combo = combo
    }

    /// The default: a keyed combination that needs no permission.
    public static let standard = HotkeyConfiguration(kind: .keyed, combo: .holdToTalk)

    /// Whether the hotkey can only be heard with Input Monitoring.
    public var needsInputMonitoring: Bool { kind == .modifierOnly }
}

/// Whether the hotkey is listening, and what the user should know about it. It is what the settings screen shows.
public struct HotkeyStatus: Sendable, Equatable {
    public enum Arming: Sendable, Equatable {
        case armed
        /// A modifier-only or fn hotkey is chosen and Input Monitoring is not granted, so it is not listening.
        case needsInputMonitoring
    }

    public var arming: Arming
    /// Secure Event Input is on: another app (usually a password field) has asked the system to keep key events to itself,
    /// and keyed shortcuts may not respond meanwhile.
    public var secureInputWarning: Bool

    public init(arming: Arming, secureInputWarning: Bool) {
        self.arming = arming
        self.secureInputWarning = secureInputWarning
    }

    /// Decides the status. It is pure, so the service and the settings screen share one rule.
    public static func evaluate(
        _ configuration: HotkeyConfiguration, inputMonitoring: PermissionStatus, secureInputActive: Bool
    ) -> HotkeyStatus {
        let isArmed = !configuration.needsInputMonitoring || inputMonitoring == .granted
        return HotkeyStatus(arming: isArmed ? .armed : .needsInputMonitoring, secureInputWarning: secureInputActive)
    }
}

/// Whether Secure Event Input is on. The live probe asks the system; a test scripts the answer.
public protocol SecureInputProbe: Sendable {
    func isActive() -> Bool
}
