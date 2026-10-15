/// The settings of command mode: hold the command hotkey over selected text, say what to do with it, and the selection
/// is replaced by the result. It is off by default (ADR 0033).
public enum CommandSettings {
    /// Whether the command hotkey is listened to. Off until the user turns it on, since a rewrite takes seconds.
    public static let enabled = SettingKey<Bool>(area: "command", name: "enabled", default: false)

    public static let all: [any AnySettingKey] = [enabled]
}

/// The limits of command mode, in characters.
public enum CommandLimits {
    /// The most text that can be selected for a command. A longer selection is refused before anything is recorded: the
    /// on-device model rewrites about 30 tokens a second, so a longer one would keep the user waiting too long.
    public static let maxSelection = 1_500
    /// The most characters of a spoken instruction. A longer one is not sent.
    public static let maxInstruction = 300

    /// How long a rewrite may take: 5 s to start the model and 40 ms for each character of instruction and selection,
    /// up to 20 s. A rewrite writes about as much as the selection, often more (a formal version adds a greeting).
    /// Measured on the real model with a 213-character request on a busy Mac, a translation took 8 to 20 s and a
    /// summary 4 to 10 s (ADR 0033), so the 3 s and 12 ms first planned would have cut nearly every command.
    public static func timeout(instruction: Int, selection: Int) -> Duration {
        min(.seconds(5) + .milliseconds(40) * max(instruction + selection, 0), .seconds(20))
    }
}

/// What a rewrite receives: the instruction the user said and the text that was selected. It runs on this Mac only:
/// there is no cloud variant of this type, so neither the selection nor the instruction can be handed to a cloud
/// provider. `CommandBoundaryTests` pins its stored properties.
public struct LocalCommandRequest: Sendable, Equatable {
    /// The raw transcript of the instruction, as the recognizer gave it.
    public let instruction: String
    /// The selected text. It lives in memory for its command only and is never stored or logged.
    public let selection: String

    public init(instruction: String, selection: String) {
        self.instruction = instruction
        self.selection = selection
    }
}

/// Rewrites a selection as the instruction says. The live one is Apple's on-device model; tests script one.
public protocol SelectionRewriter: Sendable {
    /// Where the rewrite runs. The command stage refuses a rewriter that is not local.
    var locality: Locality { get }
    func availability() async -> CleanerAvailability
    /// The rewritten text, as the model wrote it. A cancelled call throws `CancellationError`, and does so soon.
    func rewrite(_ request: LocalCommandRequest) async throws -> String
}

/// Why a command could not start. Each names the way out.
public enum CommandUnavailableReason: Sendable, Equatable {
    /// Command mode is turned off.
    case turnedOff
    /// Apple's on-device model cannot take a request on this Mac now.
    case modelUnavailable
    /// The selection is read through Accessibility, which is not allowed.
    case accessibilityMissing
}

/// Something about a command that the user should know and that is not a failure.
public enum CommandNotice: Sendable, Equatable {
    /// Nothing is selected: the command needs a selection.
    case noSelection
    /// The selection is longer than `CommandLimits.maxSelection`.
    case selectionTooLong
    /// The focused field is a password field, which is never read.
    case secureField
    /// The focused element could not be read through Accessibility.
    case selectionUnreadable
    /// The model gave nothing usable, or took too long: the text was left as it was.
    case noResult
    /// The selection changed while the model worked, so the result went to the clipboard instead.
    case selectionChanged
}
