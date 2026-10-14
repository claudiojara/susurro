import Domain
import Observation

/// The "use screen text" preference: whether Susurro reads the frontmost window with OCR to learn the names on it. The
/// preference is the user's choice (`context.ocrEnabled`, off by default). Whether OCR is active is the choice and the
/// Screen Recording permission together, so a choice that the system has not allowed leaves OCR off and says why, while
/// dictation carries on and the onboarding stays hidden: Screen Recording is a conditional permission.
@MainActor
@Observable
public final class OCRPreferenceController {
    /// What the user chose.
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let monitor: PermissionsMonitor

    public init(settings: any SettingsStore, monitor: PermissionsMonitor) {
        self.settings = settings
        self.monitor = monitor
        isEnabled = settings.value(for: ContextSettings.ocrEnabled)
    }

    /// The Screen Recording status the monitor last read.
    public var screenRecording: PermissionStatus { monitor.statuses[.screenRecording] ?? .notDetermined }

    /// Whether OCR reads the screen now: chosen, and allowed by the system.
    public var isActive: Bool { isEnabled && screenRecording == .granted }

    /// Why OCR is not reading although the user chose it, or nil when it is, or was not chosen.
    public var explanation: String? {
        guard isEnabled, !isActive else { return nil }
        return L10n.string(
            "menu.preference.screenTextOff", "Screen text is off until Screen Recording is allowed for Susurro.")
    }

    /// Tells the permissions monitor whether the saved preference needs Screen Recording. The app calls it at launch, so a
    /// permission that was revoked while the app was closed shows as inactive from the start.
    public func start() async {
        await apply(isEnabled)
    }

    /// Saves the choice. Turning OCR on without Screen Recording asks the system for it; turning it off asks for nothing.
    /// A refusal leaves the choice on and OCR inactive, with `explanation`, so that allowing the permission later
    /// activates OCR with no second step.
    public func setEnabled(_ enabled: Bool) async {
        settings.set(enabled, for: ContextSettings.ocrEnabled)
        isEnabled = enabled
        await apply(enabled)
        if enabled, screenRecording != .granted { await monitor.request(.screenRecording) }
    }

    private func apply(_ enabled: Bool) async {
        await monitor.setNeeds(
            PermissionNeeds(modifierOnlyHotkey: monitor.needs.modifierOnlyHotkey, ocrEnabled: enabled))
    }
}
