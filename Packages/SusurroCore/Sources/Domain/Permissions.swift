/// The system permissions the app can use, in the order the onboarding shows them.
public enum Permission: Sendable, Hashable, CaseIterable {
    case microphone
    case accessibility
    /// Needed to listen for a modifier-only or fn hotkey.
    case inputMonitoring
    /// Needed to read the text of the focused window with OCR.
    case screenRecording
}

extension Permission {
    /// Whether the system reports this permission only as allowed or not, so that a user who was never asked reads as
    /// denied. For these the first step is the request, which shows the system prompt that leads to System Settings, and
    /// `PermissionsChecker.status` never returns `notDetermined`. For the others, denied means the user refused.
    public var deniedMayMeanNotAsked: Bool {
        switch self {
        case .microphone, .inputMonitoring: false
        case .accessibility, .screenRecording: true
        }
    }
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionsChecker: Sendable {
    /// The permission's status now, read from the system without raising a prompt. It is never `notDetermined` for a
    /// permission whose `deniedMayMeanNotAsked` is true: the system cannot tell a refusal from no answer there, and the
    /// status is denied.
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

/// Which permissions a setup asks for and which of them hold dictation back. It is pure, so the onboarding, the menu and
/// the monitor read one rule.
///
/// Only Microphone and Accessibility are required: while one is missing dictation is disabled and the onboarding stays
/// open. Input Monitoring and Screen Recording are conditional: the setup asks for one only when it uses the feature
/// that needs it (a modifier-only hotkey, OCR), and a conditional permission that is missing never gates dictation or
/// the end of the onboarding. It leaves that one feature inactive, with an explanation.
public enum PermissionPolicy {
    /// Needed for dictation in every setup, in the order of `Permission.allCases`.
    public static let required: [Permission] = [.microphone, .accessibility]

    /// What the setup's features need beyond `required`: Input Monitoring for a modifier-only or fn hotkey, and Screen
    /// Recording when OCR is on.
    public static func conditional(for needs: PermissionNeeds) -> [Permission] {
        var permissions: [Permission] = []
        if needs.modifierOnlyHotkey { permissions.append(.inputMonitoring) }
        if needs.ocrEnabled { permissions.append(.screenRecording) }
        return permissions
    }

    /// What the setup asks the user for, the onboarding rows: `required` and `conditional(for:)`, in the order of
    /// `Permission.allCases`. A permission the setup does not use is never asked for.
    public static func requested(for needs: PermissionNeeds) -> [Permission] {
        let wanted = required + conditional(for: needs)
        return Permission.allCases.filter { wanted.contains($0) }
    }

    /// The requested permissions that are not granted, in the order of `requested(for:)`. One that has not been read is
    /// missing, so a Mac is not taken for ready before its statuses are known.
    public static func missing(
        for needs: PermissionNeeds,
        statuses: [Permission: PermissionStatus]
    ) -> [Permission] {
        requested(for: needs).filter { statuses[$0] != .granted }
    }

    /// The required permissions that are not granted. Dictation stays disabled, with the reason, until this is empty.
    /// A conditional permission is never in it.
    public static func blocking(statuses: [Permission: PermissionStatus]) -> [Permission] {
        required.filter { statuses[$0] != .granted }
    }

    /// Whether no required permission is missing. The onboarding is shown exactly while this is false, so it does not
    /// come back at launch when Microphone and Accessibility are granted, and does come back as soon as one is revoked.
    /// A conditional permission, denied or never read, does not change it.
    public static func isOnboardingComplete(statuses: [Permission: PermissionStatus]) -> Bool {
        blocking(statuses: statuses).isEmpty
    }
}
