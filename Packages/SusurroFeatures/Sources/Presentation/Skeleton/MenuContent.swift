import Domain

/// What the menu bar menu shows: why dictation is off when it is, the two required permissions, the speech model, and
/// the hotkey. It is a pure function of the statuses and the reason, so it is tested without a menu.
public struct MenuContent: Equatable, Sendable {
    public struct PermissionRow: Equatable, Sendable {
        public let permission: Permission
        public let title: String
        public let isGranted: Bool
        /// The title of the item that opens System Settings, or nil when the permission is granted.
        public let settingsActionTitle: String?
    }

    /// The reason a failed load gives is cut to this many characters.
    private static let longestReason = 80

    public let hotkeyHint: String
    /// Why dictation is off, naming the required permissions that are missing, or nil when nothing holds it back. It is
    /// the sentence the onboarding shows, from the same `DictationDisabledReason`.
    public let disabledMessage: String?
    /// The title of the item that opens the onboarding, or nil when dictation is not off.
    public let setUpTitle: String?
    public let microphone: PermissionRow
    public let accessibility: PermissionRow
    public let modelLine: String

    static func make(
        microphone: PermissionStatus, accessibility: PermissionStatus, disabledReason: DictationDisabledReason?,
        readiness: RecognizerReadiness
    ) -> MenuContent {
        MenuContent(
            hotkeyHint: "Hold Control-Option-D to dictate",
            disabledMessage: disabledReason?.message,
            setUpTitle: disabledReason == nil ? nil : "Set up Susurro…",
            microphone: row(.microphone, name: "Microphone", status: microphone),
            accessibility: row(.accessibility, name: "Accessibility", status: accessibility),
            modelLine: modelLine(for: readiness)
        )
    }

    private static func row(_ permission: Permission, name: String, status: PermissionStatus) -> PermissionRow {
        let state =
            switch status {
            case .granted: "allowed"
            case .denied: "not allowed"
            case .notDetermined: "not decided yet"
            }
        let isGranted = status == .granted
        return PermissionRow(
            permission: permission,
            title: "\(name): \(state)",
            isGranted: isGranted,
            settingsActionTitle: isGranted ? nil : "Open System Settings for \(name)…"
        )
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
