import Domain

/// Asks for the permissions that dictation needs, once, when the app launches: the microphone and then Accessibility,
/// each only if it is not granted. The prompts come one at a time, since the system shows the microphone prompt and
/// waits for an answer. Input Monitoring and Screen Recording are not needed for a keyed hotkey and are never asked for.
///
/// This is the launch-time stand-in for the onboarding that arrives in 1e and 1f, which supersedes it.
public actor PermissionPrompter {
    private let checker: any PermissionsChecker
    private var hasAsked = false

    public init(checker: any PermissionsChecker) {
        self.checker = checker
    }

    public func requestMissingPermissions() async {
        guard !hasAsked else { return }
        hasAsked = true
        for permission in [Permission.microphone, .accessibility] {
            if await checker.status(permission) != .granted { await checker.request(permission) }
        }
    }
}
