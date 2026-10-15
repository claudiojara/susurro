import DesignSystem

// The contract between the recording overlay and the code that drives it. The overlay draws these values and knows
// nothing of the core: the view model in `SusurroFeatures` maps the pipeline's states to them. Every text is ready to
// show, and an error names the way out, since the overlay cannot be clicked.

/// Everything the overlay can show. The overlay content is a pure function of this value and the input level.
public nonisolated enum OverlayViewState: Equatable, Sendable {
    /// Nothing is on screen.
    case hidden
    /// A recording was asked for and no audio has arrived yet.
    case starting(text: String)
    /// Audio is arriving. `hint` says how to stop a hands-free recording, and is nil for a hold, which ends when the
    /// key is let go.
    case recording(handsFree: Bool, text: String, hint: String?)
    /// The clip is being transcribed, or it waits for the speech model, whose load progress is `progress` (0...1).
    case transcribing(text: String, progress: Double?)
    /// The transcript is being cleaned up.
    case polishing(text: String)
    case inserted(text: String)
    /// Something the user should know that is not a failure. `symbol` is the name of an SF Symbol.
    case notice(symbol: String, text: String)
    case error(text: String)

    public var isHidden: Bool {
        self == .hidden
    }

    /// The words on screen, or nil when nothing is.
    public var text: String? {
        switch self {
        case .hidden: nil
        case .starting(let text), .transcribing(let text, _), .polishing(let text), .inserted(let text),
            .notice(_, let text), .error(let text):
            text
        case .recording(_, let text, _): text
        }
    }

    /// How far the load of the speech model has got, when that is what is on screen.
    public var progress: Double? {
        if case .transcribing(_, let progress) = self { progress } else { nil }
    }

    /// The color role of the state's symbol, or nil when nothing is on screen.
    public var tint: Tint? {
        switch self {
        case .hidden: nil
        case .starting, .transcribing, .polishing: .neutral
        case .recording: .recording
        case .inserted: .success
        case .notice: .warning
        case .error: .error
        }
    }

    /// The name of the SF Symbol for the state, or nil when nothing is on screen.
    public var symbol: String? {
        switch self {
        case .hidden: nil
        case .starting: "mic"
        case .recording: "mic.fill"
        case .transcribing(_, let progress): progress == nil ? "waveform" : "arrow.down.circle"
        case .polishing: "sparkles"
        case .inserted: "checkmark.circle.fill"
        case .notice(let symbol, _): symbol
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

/// What the overlay needs from the code behind it.
@MainActor
public protocol OverlayViewModeling: AnyObject {
    var state: OverlayViewState { get }
    /// The input level of the microphone, from 0 to 1, no more often than 30 times a second.
    var level: Double { get }
    /// The id of the overlay variant the user selected.
    var styleID: String { get }
    /// The words heard so far while recording, for a style that shows them. Display only: it is never what is pasted.
    var transcript: String { get }
}

extension OverlayViewModeling {
    public var transcript: String { "" }
}
