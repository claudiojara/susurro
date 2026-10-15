// The contract between the recorder of the hotkey and the code that drives it. The recorder draws this value and calls the
// intents; it knows nothing of the keyboard, so the view model in `SusurroFeatures` listens to the keys, decides whether
// a shortcut is allowed, and says why not in words that are ready to show.

public nonisolated struct HotkeyRecorderState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// The shortcut in use is shown and a button offers to change it.
        case idle
        /// Waiting for the user to press the new shortcut. `held` are the modifier keys that are down now, one key cap
        /// each, such as `⌃`, `⌥`: none before the first press.
        case listening(held: [String])
    }

    public let phase: Phase
    /// Why the last shortcut was refused, or nil. The recorder goes on listening, so the user can press another.
    public let rejection: String?
    /// Whether the shortcut in use is not the default one, so that a button can bring the default back.
    public let canRestoreDefault: Bool
    /// The title of the button that brings the default back, or nil for "Restore default". A shortcut that is unassigned
    /// by default calls it something else, such as "Remove shortcut".
    public let restoreTitle: String?

    public init(phase: Phase, rejection: String?, canRestoreDefault: Bool, restoreTitle: String? = nil) {
        self.phase = phase
        self.rejection = rejection
        self.canRestoreDefault = canRestoreDefault
        self.restoreTitle = restoreTitle
    }
}

/// What the recorder of the hotkey needs from the code behind it. A shortcut that is allowed is applied at once: the
/// hotkey in use changes and the settings show it.
@MainActor
public protocol HotkeyRecorderModeling: AnyObject {
    var state: HotkeyRecorderState { get }

    /// Starts listening for the new shortcut.
    func begin()
    /// Stops listening and keeps the shortcut in use.
    func cancel()
    /// Goes back to the default shortcut.
    func restoreDefault()
}

/// What the recorder can ask for, as closures, so that the view is a pure function of its state and its actions. A
/// preview or a snapshot passes `.none`.
public struct HotkeyRecorderActions {
    public var begin: () -> Void
    public var cancel: () -> Void
    public var restoreDefault: () -> Void

    public static let none = HotkeyRecorderActions(begin: {}, cancel: {}, restoreDefault: {})

    public init(begin: @escaping () -> Void, cancel: @escaping () -> Void, restoreDefault: @escaping () -> Void) {
        self.begin = begin
        self.cancel = cancel
        self.restoreDefault = restoreDefault
    }

    /// The actions that call the intents of a view model.
    @MainActor
    public init(model: any HotkeyRecorderModeling) {
        self.init(
            begin: { model.begin() }, cancel: { model.cancel() }, restoreDefault: { model.restoreDefault() })
    }
}
