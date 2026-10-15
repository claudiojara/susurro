import DesignSystem
import Domain
import SusurroUI
import Testing

@testable import Presentation

@Suite("Overlay mapping for command mode")
struct CommandOverlayMappingTests {
    @Test("while the model rewrites, the overlay says so and that Esc cancels")
    func rewriting() {
        let mapped = OverlayMapping.viewState(for: .rewriting)

        #expect(mapped == .polishing(text: "Rewriting… Esc cancels"))
        #expect(mapped.tint == .neutral)
    }

    @Test("a replaced selection is a success that says how to undo it")
    func replaced() {
        let mapped = OverlayMapping.viewState(for: .replaced)

        #expect(mapped == .inserted(text: "Replaced · ⌘Z undoes"))
        #expect(mapped.tint == .success)
    }

    @Test(
        "each command notice is a warning with words of its own",
        arguments: [
            (CommandNotice.noSelection, "Select text, then hold the command key"),
            (.selectionTooLong, "The selection is too long for a command"),
            (.secureField, "Password fields are never read"),
            (.selectionUnreadable, "Could not read the selection. Check Accessibility in the Susurro menu."),
            (.noResult, "No result; the text was left as is"),
            (.selectionChanged, "Selection changed; result on clipboard"),
        ])
    func notices(notice: CommandNotice, text: String) {
        let mapped = OverlayMapping.viewState(for: .notice(.command(notice)))

        #expect(mapped.tint == .warning)
        #expect(mapped.text == text)
    }

    @Test(
        "a command that cannot run names the way out",
        arguments: [
            (CommandUnavailableReason.turnedOff, "Command mode is off. Open the Susurro menu."),
            (.modelUnavailable, "Apple Intelligence is not available. Open the Susurro menu."),
            (.accessibilityMissing, "Command mode needs Accessibility. Open the Susurro menu to turn it on."),
        ])
    func unavailable(reason: CommandUnavailableReason, text: String) {
        #expect(OverlayMapping.viewState(for: .error(.commandUnavailable(reason))) == .error(text: text))
    }

    @Test("the rewriting state stays until the pipeline moves on, and the replaced one is held like a notice")
    func timing() {
        #expect(OverlayTiming.standard.dwell(for: .rewriting) == nil)
        #expect(OverlayTiming.standard.dwell(for: .replaced) == OverlayTiming.standard.notice)
    }
}
