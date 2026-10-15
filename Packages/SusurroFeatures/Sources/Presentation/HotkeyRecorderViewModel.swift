import Domain
import Observation
import SusurroUI

/// Records a new hotkey for the Hotkey tab of the settings. While it listens it feeds the keys of the user to
/// `HotkeyCapture`, shows the modifier keys that are held, and, when the user has pressed a shortcut, asks
/// `HotkeyValidation` whether it is allowed: an allowed one is stored in the settings, where the hotkey service reads it and
/// starts to listen to it at once, and one that is refused is told with the reason and the recorder goes on listening. Esc,
/// the Cancel button, or the end of the keys (the window lost them) stop it with the hotkey as it was.
///
/// The same recorder changes the command mode hotkey and the shortcut that pastes the last dictation, through other
/// `HotkeyBinding`s. No shortcut of the app may take the keys of another.
@MainActor
@Observable
public final class HotkeyRecorderViewModel: HotkeyRecorderModeling {
    @ObservationIgnored private let binding: HotkeyBinding
    @ObservationIgnored private let source: any HotkeyCaptureSource
    @ObservationIgnored private let isTakenBySystem: @MainActor (HotkeyCombo) -> Bool
    @ObservationIgnored private var listening: Task<Void, Never>?
    /// Tells a recording from the one before it, so that the end of an old one cannot stop a new one.
    @ObservationIgnored private var recording = 0

    private var isListening = false
    private var capture = HotkeyCapture()
    private var rejection: String?
    /// Counts the changes made to the hotkey. `state` reads it, so it is drawn again after each of them, though the settings
    /// store is not observable.
    private var revision = 0

    /// - Parameters:
    ///   - source: Where the keys come from while the recorder listens.
    ///   - isTakenBySystem: Whether an enabled shortcut of System Settings already uses the combo.
    public convenience init(
        settings: any SettingsStore, source: any HotkeyCaptureSource,
        isTakenBySystem: @escaping @MainActor (HotkeyCombo) -> Bool
    ) {
        self.init(binding: .dictation(settings), source: source, isTakenBySystem: isTakenBySystem)
    }

    /// - Parameter binding: Which shortcut the recorder changes, and its rules.
    public init(
        binding: HotkeyBinding, source: any HotkeyCaptureSource,
        isTakenBySystem: @escaping @MainActor (HotkeyCombo) -> Bool
    ) {
        self.binding = binding
        self.source = source
        self.isTakenBySystem = isTakenBySystem
    }

    public var state: HotkeyRecorderState {
        _ = revision
        return HotkeyRecorderState(
            phase: isListening ? .listening(held: capture.held.caps) : .idle,
            rejection: rejection,
            canRestoreDefault: !binding.isDefault(),
            restoreTitle: binding.restoreTitle())
    }

    public func begin() {
        guard !isListening else { return }
        isListening = true
        capture = HotkeyCapture()
        rejection = nil
        recording += 1
        let mine = recording
        let inputs = source.inputs()
        listening = Task {
            for await input in inputs {
                guard mine == recording else { return }
                handle(input)
            }
            // The keys ended: the window lost them, or the recorder stopped itself.
            if mine == recording { stop() }
        }
    }

    public func cancel() {
        stop()
    }

    public func restoreDefault() {
        stop()
        binding.reset()
        revision &+= 1
    }

    /// Takes one key of the recording.
    private func handle(_ input: HotkeyCaptureInput) {
        guard isListening else { return }
        switch capture.handle(input) {
        case .none:
            break
        case .cancel:
            stop()
        case .candidate(let configuration):
            choose(configuration)
        }
    }

    private func choose(_ configuration: HotkeyConfiguration) {
        if let reason = binding.rejection(configuration, isTakenBySystem) {
            rejection = SettingsCopy.rejection(reason)
            return
        }
        binding.store(configuration)
        stop()
    }

    private func stop() {
        listening?.cancel()
        listening = nil
        recording += 1
        isListening = false
        capture = HotkeyCapture()
        rejection = nil
        revision &+= 1
    }
}

/// A shortcut the recorder can change: how it is read, stored, and reset, and the rules it follows.
public struct HotkeyBinding {
    /// Whether the shortcut is its default, so there is nothing to restore.
    var isDefault: @MainActor () -> Bool
    var store: @MainActor (HotkeyConfiguration) -> Void
    var reset: @MainActor () -> Void
    /// Why a shortcut is refused, or nil, given whether a system shortcut takes the combo.
    var rejection: @MainActor (HotkeyConfiguration, (HotkeyCombo) -> Bool) -> HotkeyRejection?
    /// The title of the button that resets it, or nil for the recorder's own. It is read each time, so it follows the
    /// interface language.
    var restoreTitle: @MainActor () -> String?

    /// The dictation hotkey (`HotkeySettings`).
    public static func dictation(_ settings: any SettingsStore) -> HotkeyBinding {
        hold(.dictate, settings)
    }

    /// The command mode hotkey (`HotkeySettings.commandKind` and `commandCombo`).
    public static func command(_ settings: any SettingsStore) -> HotkeyBinding {
        hold(.command, settings)
    }

    /// A hotkey that is held: the rules of every hotkey, and none of the app's other shortcuts.
    private static func hold(_ role: HotkeyRole, _ settings: any SettingsStore) -> HotkeyBinding {
        HotkeyBinding(
            isDefault: { settings.hotkeyConfiguration(for: role) == .defaultHotkey(for: role) },
            store: { settings.setHotkey($0, for: role) },
            reset: { settings.resetHotkey(for: role) },
            rejection: {
                HotkeyValidation.rejection(
                    of: $0, isTakenBySystem: $1, inUse: settings.shortcutsInUse(except: role))
            },
            restoreTitle: { nil })
    }

    /// The shortcut that pastes the last dictation (`PasteLastSettings`). It is unassigned by default, so resetting it
    /// removes it.
    public static func pasteLast(_ settings: any SettingsStore) -> HotkeyBinding {
        HotkeyBinding(
            isDefault: { settings.value(for: PasteLastSettings.combo) == nil },
            store: { settings.set($0.combo, for: PasteLastSettings.combo) },
            reset: { settings.remove(PasteLastSettings.combo) },
            rejection: {
                PasteLastValidation.rejection(
                    of: $0, dictation: settings.hotkeyConfiguration(), isTakenBySystem: $1,
                    inUse: [settings.hotkeyConfiguration(for: .command)])
            },
            restoreTitle: { SettingsCopy.removeShortcut })
    }
}
