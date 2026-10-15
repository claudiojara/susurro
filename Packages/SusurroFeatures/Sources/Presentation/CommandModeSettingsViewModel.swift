import Domain
import Observation
import SusurroUI

/// The command mode card of the settings: the switch (`command.enabled`), the command hotkey as key caps, and a warning
/// when Apple Intelligence cannot rewrite on this Mac. The recorder of the command hotkey is a `HotkeyRecorderViewModel`
/// for the command role, in the card's slot.
@MainActor
@Observable
public final class CommandModeSettingsViewModel: CommandModeSettingsModeling {
    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let shortcut: @MainActor (HotkeyConfiguration) -> [String]
    @ObservationIgnored private let modelAvailable: @Sendable () async -> Bool

    private var isModelAvailable = true
    /// Counts the changes of the settings the card shows. `state` reads it, so the card is drawn again after each of
    /// them, though the settings store is not observable.
    private var revision = 0

    /// - Parameters:
    ///   - shortcut: The key caps of a hotkey, which the platform knows.
    ///   - modelAvailable: Whether Apple's on-device model can take a request on this Mac.
    public init(
        settings: any SettingsStore, shortcut: @escaping @MainActor (HotkeyConfiguration) -> [String],
        modelAvailable: @escaping @Sendable () async -> Bool
    ) {
        self.settings = settings
        self.shortcut = shortcut
        self.modelAvailable = modelAvailable
    }

    public var state: CommandModeSettingsState {
        _ = revision
        return CommandModeSettingsState(
            isEnabled: settings.value(for: CommandSettings.enabled),
            shortcut: shortcut(settings.hotkeyConfiguration(for: .command)),
            warning: isModelAvailable ? nil : CommandModeCopy.modelUnavailable)
    }

    public func setEnabled(_ enabled: Bool) {
        settings.set(enabled, for: CommandSettings.enabled)
        revision &+= 1
    }

    public func follow() async {
        let changes = settings.changes()
        isModelAvailable = await modelAvailable()
        for await change in changes
        where change.name.hasPrefix("command.") || change.name.hasPrefix("hotkey.command") {
            revision &+= 1
        }
    }
}

enum CommandModeCopy {
    static var modelUnavailable: String {
        L10n.string(
            "settings.command.modelUnavailable",
            "Apple Intelligence is not available on this Mac now, so command mode cannot rewrite text.")
    }
}
