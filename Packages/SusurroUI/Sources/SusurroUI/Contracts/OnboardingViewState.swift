// The contract between the onboarding screen and the code that drives it. The screen draws these values and calls the
// intents; it knows nothing of the core, so the permissions have a name of their own here and the view model in
// `SusurroFeatures` maps them. Every text is ready to show.

/// A permission the onboarding can ask for.
public nonisolated enum OnboardingPermission: String, CaseIterable, Hashable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring
    case screenRecording
}

/// Where a permission stands for the user.
public nonisolated enum OnboardingRowStatus: Equatable, Sendable {
    /// Allowed.
    case granted
    /// The user has not been asked yet.
    case notAsked
    /// Not allowed.
    case denied
    /// The user was asked to act, in a prompt or in System Settings, and nothing has changed yet.
    case waiting
    /// Still not allowed a while after the user came back from System Settings, so the grant may be stale and the
    /// troubleshooting steps are shown.
    case stale
}

/// The one step a row offers.
public nonisolated struct OnboardingAction: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Ask the system, which may show its prompt.
        case request
        /// Open the System Settings pane of the permission.
        case openSettings
    }

    public let kind: Kind
    public let title: String

    public init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }
}

/// One permission in the checklist.
public nonisolated struct OnboardingRowState: Equatable, Sendable, Identifiable {
    public let id: OnboardingPermission
    public let title: String
    /// Why the app needs the permission.
    public let why: String
    /// An optional permission never holds dictation or the Done button back.
    public let isOptional: Bool
    /// Which feature an optional permission is for, and that dictation works without it. Nil for a required one.
    public let featureNote: String?
    public let status: OnboardingRowStatus
    /// Nil when there is nothing to do: the permission is granted, or a prompt is up.
    public let action: OnboardingAction?
    /// The troubleshooting steps. Present only when the status is `stale`.
    public let staleGuidance: String?

    public init(
        id: OnboardingPermission,
        title: String,
        why: String,
        isOptional: Bool,
        featureNote: String?,
        status: OnboardingRowStatus,
        action: OnboardingAction?,
        staleGuidance: String?
    ) {
        self.id = id
        self.title = title
        self.why = why
        self.isOptional = isOptional
        self.featureNote = featureNote
        self.status = status
        self.action = action
        self.staleGuidance = staleGuidance
    }
}

/// Everything the onboarding screen shows.
public nonisolated struct OnboardingViewState: Equatable, Sendable {
    public let rows: [OnboardingRowState]
    /// On once no required permission is missing.
    public let isDoneEnabled: Bool
    /// Why dictation is off, naming the required permissions that are missing. Nil when nothing holds it back.
    public let dictationDisabledMessage: String?

    public init(rows: [OnboardingRowState], isDoneEnabled: Bool, dictationDisabledMessage: String?) {
        self.rows = rows
        self.isDoneEnabled = isDoneEnabled
        self.dictationDisabledMessage = dictationDisabledMessage
    }
}

/// What the onboarding screen needs from the code behind it.
@MainActor
public protocol OnboardingViewModeling: AnyObject {
    var state: OnboardingViewState { get }

    /// Asks the system for the permission.
    func request(_ permission: OnboardingPermission) async
    /// Opens the System Settings pane of the permission.
    func openSettings(_ permission: OnboardingPermission)
    /// Reads the statuses now, for a "check again" button.
    func recheck() async
    /// The screen is on screen: the statuses are checked every second until it goes.
    func onboardingDidAppear()
    func onboardingDidDisappear()
}
