import Observation

/// Decides when the onboarding opens. It opens when a required permission turns out to be missing: at launch, once the
/// statuses are read, and again when one is revoked later. It opens once for each time the permissions go from complete
/// (or not yet known) to missing, so a window the user closed stays closed until the next time. The menu can open it
/// whenever a required permission is missing.
///
/// What it watches is `PermissionsMonitor.needsOnboarding`, which is false until the first read, so a launch with
/// everything allowed never shows it, and a conditional permission that is denied never does.
@MainActor
public final class OnboardingPresenter {
    private let monitor: PermissionsMonitor
    private let surface: any OnboardingSurface

    public init(monitor: PermissionsMonitor, surface: any OnboardingSurface) {
        self.monitor = monitor
        self.surface = surface
    }

    /// Watches the monitor until the task is cancelled.
    public func run() async {
        let monitor = monitor
        var wasNeeded = false
        for await isNeeded in Observations({ monitor.needsOnboarding }) {
            if isNeeded && !wasNeeded { surface.show() }
            wasNeeded = isNeeded
        }
    }

    /// Opens the onboarding at the user's request.
    public func show() {
        surface.show()
    }
}
