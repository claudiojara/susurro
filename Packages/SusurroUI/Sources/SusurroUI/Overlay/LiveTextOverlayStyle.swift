import DesignSystem
import SwiftUI

/// A wider panel that shows the words while they are spoken. The words are a preview, transcribed every second or so
/// while recording; the text that is pasted is the transcript of the whole recording, which can differ from them.
public struct LiveTextOverlayStyle: OverlayStyle {
    public static let id = "liveText"
    public static let showsLiveTranscript = true

    public init() {}

    public func body(state: OverlayViewState, level: Double) -> AnyView {
        body(state: state, level: level, transcript: "")
    }

    public func body(state: OverlayViewState, level: Double, transcript: String) -> AnyView {
        AnyView(LiveTextOverlayHUD(state: state, level: level, transcript: transcript))
    }
}

/// What the live text style draws: the symbol and the words of the state, and while recording the end of what was heard
/// so far, in a fixed number of lines, so that the panel keeps its size as the words come. A pure function of the state,
/// the level, the words, and the theme.
struct LiveTextOverlayHUD: View {
    @Environment(\.theme) private var theme
    let state: OverlayViewState
    let level: Double
    let transcript: String

    /// The lines kept for the words, whether or not there are any yet.
    static let lines = 3
    /// The most of the words that is shown: about what fits in the lines, so the newest words are always on screen.
    static let maxCharacters = 160

    var body: some View {
        if let text = state.text, let symbol = state.symbol {
            let shape = RoundedRectangle(cornerRadius: theme.overlay.cornerRadius, style: .continuous)
            VStack(alignment: .leading, spacing: theme.spacing(.sm)) {
                HStack(alignment: .top, spacing: theme.spacing(.md)) {
                    Icon(symbol, style: .headline, tint: state.tint)
                    TextLabel(text, style: .bodyEmphasized)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                details
            }
            .padding(.horizontal, theme.spacing(.lg))
            .padding(.vertical, theme.spacing(.md))
            .frame(width: theme.layout(.overlayWideWidth), alignment: .leading)
            .background(theme.swiftUIColor(.surfaceOverlay), in: shape)
            .overlay(shape.strokeBorder(theme.swiftUIColor(.borderSubtle)))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var details: some View {
        switch state {
        case .recording(_, let text, let hint):
            // A blank line, not an empty text, which would take no room until the first words came.
            let words = LiveTranscriptTail.tail(of: transcript, maxCharacters: Self.maxCharacters)
            TextLabel(words.isEmpty ? " " : words, style: .body)
                .lineLimit(Self.lines, reservesSpace: true)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            LevelBar(level: level, tint: .recording, label: text)
            if let hint {
                TextLabel(hint, style: .caption, tint: .neutral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .transcribing(let text, let progress?):
            LevelBar(level: progress, tint: .accent, label: text)
        case .hidden, .starting, .transcribing, .polishing, .inserted, .notice, .error:
            EmptyView()
        }
    }
}

/// The end of a transcript that is too long to show whole: it starts at a word, after an ellipsis.
enum LiveTranscriptTail {
    static func tail(of transcript: String, maxCharacters: Int) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxCharacters else { return text }
        let end = text.suffix(maxCharacters)
        let startsAtWord = text.dropLast(maxCharacters).last?.isWhitespace ?? true
        let kept = startsAtWord ? end : (end.firstIndex(where: \.isWhitespace).map { end[$0...] } ?? end)
        return "…" + kept.trimmingCharacters(in: .whitespaces)
    }
}
