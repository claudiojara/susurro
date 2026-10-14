/// The system permissions the app can use, in the order the onboarding shows them.
public enum Permission: Sendable, Hashable, CaseIterable {
    case microphone
    case accessibility
    /// Needed to listen for a modifier-only or fn hotkey.
    case inputMonitoring
    /// Needed to read the text of the focused window with OCR.
    case screenRecording
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionsChecker: Sendable {
    func status(_ permission: Permission) async -> PermissionStatus
    /// Asks the system for the permission, which may show its prompt. A permission that is already decided is not
    /// asked again; the user changes it in System Settings.
    func request(_ permission: Permission) async
}

/// The parts of the user's setup that decide which permissions the app needs beyond Microphone and Accessibility.
public struct PermissionNeeds: Sendable, Equatable {
    /// The hotkey is a modifier-only combination or the fn key, which a keyed hotkey is not.
    public var modifierOnlyHotkey: Bool
    public var ocrEnabled: Bool

    /// The default setup: a keyed hotkey and OCR off.
    public init(modifierOnlyHotkey: Bool = false, ocrEnabled: Bool = false) {
        self.modifierOnlyHotkey = modifierOnlyHotkey
        self.ocrEnabled = ocrEnabled
    }
}

/// Which permissions a setup needs and whether they are all granted. It is pure, so the onboarding, the menu and the
/// monitor read one rule. A permission the setup does not need is never asked for and never held against it.
public enum PermissionPolicy {
    /// What a setup needs, in the order of `Permission.allCases`. Microphone and Accessibility are always needed, Input
    /// Monitoring only for a modifier-only or fn hotkey, and Screen Recording only when OCR is on.
    public static func required(for needs: PermissionNeeds) -> [Permission] {
        Permission.allCases.filter { permission in
            switch permission {
            case .microphone, .accessibility: true
            case .inputMonitoring: needs.modifierOnlyHotkey
            case .screenRecording: needs.ocrEnabled
            }
        }
    }

    /// The needed permissions that are not granted, in the order of `required(for:)`. One that has not been read is
    /// missing, so a Mac is not taken for ready before its statuses are known.
    public static func missing(
        for needs: PermissionNeeds,
        statuses: [Permission: PermissionStatus]
    ) -> [Permission] {
        required(for: needs).filter { statuses[$0] != .granted }
    }

    /// Whether every needed permission is granted. The onboarding is shown exactly while this is false, so it does not
    /// come back at launch when everything is granted and does come back as soon as one is revoked or newly needed.
    public static func isOnboardingComplete(
        for needs: PermissionNeeds,
        statuses: [Permission: PermissionStatus]
    ) -> Bool {
        missing(for: needs, statuses: statuses).isEmpty
    }
}
