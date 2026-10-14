import Domain

/// What the menu bar menu shows: what a missing permission costs when one is missing, the two required permissions, the
/// speech model, and the hotkey. It is a pure function of the statuses and the restriction, so it is tested without a
/// menu.
public struct MenuContent: Equatable, Sendable {
    public struct PermissionRow: Equatable, Sendable {
        /// The item that takes the next step for the permission.
        public struct Action: Equatable, Sendable {
            public let kind: PermissionStep.Action
            public let title: String
        }

        public let permission: Permission
        public let title: String
        public let isGranted: Bool
        /// The step that fits, or nil when the permission is granted or its prompt is up. It is the onboarding's
        /// (`PermissionStep`): allow it when it was never asked, open System Settings when it was refused.
        public let action: Action?
    }

    /// A switch in the menu: clean up the text, use the app's context, use screen text.
    public struct Preference: Equatable, Sendable {
        public enum Kind: Hashable, Sendable {
            case cleanup
            case appContext
            case screenText
        }

        public let kind: Kind
        public let title: String
        public let isOn: Bool
        /// Why the switch has no effect although it is on, or nil.
        public let note: String?

        public init(kind: Kind, title: String, isOn: Bool, note: String?) {
            self.kind = kind
            self.title = title
            self.isOn = isOn
            self.note = note
        }
    }

    /// The reason a failed load gives is cut to this many characters.
    private static let longestReason = 80

    public let hotkeyHint: String
    /// What the missing required permissions cost, that dictation is off or that the text goes to the clipboard, or nil
    /// when none is missing. It is the sentence the onboarding shows, from the same `DictationRestriction`.
    public let restrictionMessage: String?
    /// The title of the item that opens the onboarding, or nil when no required permission is missing.
    public let setUpTitle: String?
    public let microphone: PermissionRow
    public let accessibility: PermissionRow
    public let modelLine: String
    /// The switches, below the permissions. None while the app has no preferences to show.
    public let preferences: [Preference]

    static func make(
        microphone: PermissionStatus, accessibility: PermissionStatus,
        followUps: [Permission: PermissionsMonitor.FollowUp] = [:], restriction: DictationRestriction?,
        readiness: RecognizerReadiness, preferences: [Preference] = []
    ) -> MenuContent {
        MenuContent(
            hotkeyHint: "Hold Control-Option-D to dictate",
            restrictionMessage: restriction?.message,
            setUpTitle: restriction == nil ? nil : "\(OnboardingCopy.title)…",
            microphone: row(.microphone, name: "Microphone", status: microphone, followUp: followUps[.microphone]),
            accessibility: row(
                .accessibility, name: "Accessibility", status: accessibility, followUp: followUps[.accessibility]),
            modelLine: modelLine(for: readiness),
            preferences: preferences
        )
    }

    private static func row(
        _ permission: Permission, name: String, status: PermissionStatus, followUp: PermissionsMonitor.FollowUp?
    ) -> PermissionRow {
        let state =
            switch status {
            case .granted: "allowed"
            case .denied: "not allowed"
            case .notDetermined: "not decided yet"
            }
        let step = PermissionStep.make(permission: permission, status: status, followUp: followUp)
        return PermissionRow(
            permission: permission,
            title: "\(name): \(state)",
            isGranted: status == .granted,
            action: step.action.map { PermissionRow.Action(kind: $0, title: title(of: $0, name: name)) }
        )
    }

    private static func title(of action: PermissionStep.Action, name: String) -> String {
        switch action {
        case .request: "Allow \(name)…"
        case .openSettings: "Open System Settings for \(name)…"
        }
    }

    private static func modelLine(for readiness: RecognizerReadiness) -> String {
        switch readiness {
        case .ready:
            return "Speech model: ready"
        case .loading(let progress):
            let percent = Int((progress.loadFraction * 100).rounded())
            return percent == 0 ? "Speech model: preparing…" : "Speech model: preparing… \(percent)%"
        case .notInstalled:
            return "Speech model: not installed. Restart Susurro to download it."
        case .unavailable(let reason, let retryable):
            let shown = reason.count > longestReason ? "\(reason.prefix(longestReason))…" : reason
            let wayOut = retryable ? "Susurro will retry loading the model shortly." : "Restart Susurro."
            return "Speech model: could not load (\(shown)). \(wayOut)"
        }
    }
}
