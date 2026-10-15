import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// A look that draws the words the user is saying and nothing else.
struct TranscriptEchoStyle: OverlayStyle {
    static let id = "echo"
    static let showsLiveTranscript = true

    func body(state: OverlayViewState, level: Double) -> AnyView { AnyView(EmptyView()) }

    func body(state: OverlayViewState, level: Double, transcript: String) -> AnyView {
        AnyView(Text(transcript))
    }
}

@MainActor
@Suite("Overlay styles")
struct OverlayStylesTests {
    private static let recording = OverlayViewState.recording(handsFree: false, text: "Listening…", hint: nil)
    private static let transcript = "mañana tengo una reunión a las diez"
    private let size = CGSize(width: 560, height: 200)

    private func png(of view: some View) -> Data {
        SnapshotSupport.pngData(of: view, size: size, scheme: .light)
    }

    // MARK: The registry

    @Test("the app has the pill, the minimal pill and the live text, and only the live text shows the words")
    func standardStyles() {
        let registry = OverlayStyleRegistry.standard()

        #expect(registry.ids == ["liveText", "minimal", "pill"])
        #expect(registry.liveTranscriptStyleIDs == ["liveText"])
        for id in registry.ids { #expect(type(of: registry.style(for: id)).id == id) }
        #expect(registry.reportedErrors.isEmpty)
    }

    @Test("the container hands the words of the model to the style, and a style that ignores them is unchanged")
    func containerPassesTheTranscript() {
        let registry = OverlayStyleRegistry.standard()
        registry.register(TranscriptEchoStyle())
        let model = StubOverlayModel(state: Self.recording, styleID: TranscriptEchoStyle.id)
        model.transcript = Self.transcript

        #expect(png(of: OverlayContainer(model: model, registry: registry)) == png(of: Text(Self.transcript)))
        #expect(
            png(of: PillOverlayStyle().body(state: Self.recording, level: 0.5, transcript: Self.transcript))
                == png(of: PillOverlayStyle().body(state: Self.recording, level: 0.5)))
    }

    // MARK: Minimal

    @Test("the minimal pill is as wide as the theme's compact width, and narrower than the pill")
    func minimalWidth() {
        var theme = Theme.default
        let view = MinimalOverlayStyle().body(state: Self.recording, level: 0.5)
        let standard = SnapshotSupport.idealSize(of: view, theme: theme, scheme: .light)
        theme.layout["overlayCompactWidth"] = 150
        let narrow = SnapshotSupport.idealSize(of: view, theme: theme, scheme: .light)

        #expect(standard.width == CGFloat(Theme.default.layout["overlayCompactWidth"]!))
        #expect(standard.width < CGFloat(Theme.default.overlay.width))
        #expect(narrow.width == 150)
    }

    @Test("the minimal pill moves its meter with the level while recording, and an error still says what to do")
    func minimalContent() {
        let style = MinimalOverlayStyle()
        let error = OverlayViewState.error(text: "Microphone access is off. Open the Susurro menu to turn it on.")

        #expect(
            png(of: style.body(state: Self.recording, level: 0.1))
                != png(of: style.body(state: Self.recording, level: 0.9)))
        #expect(
            SnapshotSupport.idealSize(of: style.body(state: error, level: 0), scheme: .light).height
                > SnapshotSupport.idealSize(of: style.body(state: Self.recording, level: 0), scheme: .light).height)
    }

    // MARK: Live text

    @Test("the live text panel is as wide as the theme's wide width")
    func liveTextWidth() {
        var theme = Theme.default
        let view = LiveTextOverlayStyle().body(state: Self.recording, level: 0.5, transcript: Self.transcript)
        let standard = SnapshotSupport.idealSize(of: view, theme: theme, scheme: .light)
        theme.layout["overlayWideWidth"] = 600
        let wide = SnapshotSupport.idealSize(of: view, theme: theme, scheme: .light)

        #expect(standard.width == CGFloat(Theme.default.layout["overlayWideWidth"]!))
        #expect(wide.width == 600)
    }

    @Test("while recording the panel shows the words, and it keeps its height as they come, so the panel never jumps")
    func liveTextShowsTheWords() {
        let style = LiveTextOverlayStyle()
        let empty = style.body(state: Self.recording, level: 0.5, transcript: "")
        let some = style.body(state: Self.recording, level: 0.5, transcript: Self.transcript)
        let many = style.body(
            state: Self.recording, level: 0.5, transcript: String(repeating: Self.transcript + " ", count: 20))

        #expect(png(of: empty) != png(of: some))
        let heights = [empty, some, many].map { SnapshotSupport.idealSize(of: $0, scheme: .light).height }
        #expect(Set(heights).count == 1, "\(heights)")
    }

    @Test("the words show only while recording")
    func liveTextOnlyWhileRecording() {
        let style = LiveTextOverlayStyle()
        let transcribing = OverlayViewState.transcribing(text: "Transcribing…", progress: nil)

        #expect(
            png(of: style.body(state: transcribing, level: 0.5, transcript: Self.transcript))
                == png(of: style.body(state: transcribing, level: 0.5, transcript: "")))
    }

    @Test("a long transcript shows its end, from the start of a word, after an ellipsis")
    func tail() {
        #expect(LiveTranscriptTail.tail(of: "short text", maxCharacters: 20) == "short text")
        #expect(LiveTranscriptTail.tail(of: "  padded  ", maxCharacters: 20) == "padded")
        #expect(LiveTranscriptTail.tail(of: "one two three four five", maxCharacters: 15) == "…three four five")
        #expect(LiveTranscriptTail.tail(of: "one two three four five", maxCharacters: 12) == "…four five")
        #expect(LiveTranscriptTail.tail(of: "one two three four five", maxCharacters: 10) == "…four five")
        #expect(LiveTranscriptTail.tail(of: "supercalifragilistic", maxCharacters: 5) == "…istic")
    }
}
