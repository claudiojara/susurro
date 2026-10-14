// The contract between the onboarding screen and the code that drives it. The screen draws these values and calls the
// intents; it knows nothing of the core, so the permissions have a name of their own here and the view model in
// `SusurroFeatures` maps them. Every text is ready to show, and every word on the screen is in these values: the views
// write none, so the words have one owner, the code that builds the state.

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
    /// Still not allowed a while after the user came back from System Settings, so the grant may be stale. `guidance`
    /// holds the troubleshooting steps that fit the permission.
    case stale(guidance: String)
}

/// Whether a permission holds dictation back.
public nonisolated enum OnboardingRequirement: Equatable, Sendable {
    case required
    /// Never holds dictation or the Done button back. `featureNote` says which feature the permission is for, and that
    /// dictation works without it.
    case optional(featureNote: String)
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
    public let requirement: OnboardingRequirement
    public let status: OnboardingRowStatus
    /// The word for `status` that the row shows in its pill, such as "Allowed".
    public let statusText: String
    /// Nil when there is nothing to do: the permission is granted, or a prompt is up.
    public let action: OnboardingAction?

    public init(
        id: OnboardingPermission,
        title: String,
        why: String,
        requirement: OnboardingRequirement,
        status: OnboardingRowStatus,
        statusText: String,
        action: OnboardingAction?
    ) {
        self.id = id
        self.title = title
        self.why = why
        self.requirement = requirement
        self.status = status
        self.statusText = statusText
        self.action = action
    }
}

/// Everything the onboarding screen shows.
public nonisolated struct OnboardingViewState: Equatable, Sendable {
    public let title: String
    /// What the permissions are for, under the title.
    public let subtitle: String
    public let rows: [OnboardingRowState]
    /// What the missing required permissions cost: that dictation is off, that the text goes to the clipboard, or both.
    /// Nil when none is missing.
    public let restrictionMessage: String?
    /// The title of the button that reads the statuses again.
    public let recheckTitle: String
    /// The title of the button that finishes the onboarding.
    public let doneTitle: String
    /// On once no required permission is missing.
    public let isDoneEnabled: Bool

    public init(
        title: String,
        subtitle: String,
        rows: [OnboardingRowState],
        restrictionMessage: String?,
        recheckTitle: String,
        doneTitle: String,
        isDoneEnabled: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.restrictionMessage = restrictionMessage
        self.recheckTitle = recheckTitle
        self.doneTitle = doneTitle
        self.isDoneEnabled = isDoneEnabled
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
    /// Reads the statuses now, for a "check again" button. They are also read every second without the screen's help.
    func recheck() async
}
