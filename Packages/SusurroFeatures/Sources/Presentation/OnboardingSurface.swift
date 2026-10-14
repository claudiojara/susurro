/// Where the onboarding is shown: a window in the app, a recorder in a test.
@MainActor
public protocol OnboardingSurface {
    /// Puts the onboarding in front of the user, and brings the app forward if it is not.
    func show()
}
