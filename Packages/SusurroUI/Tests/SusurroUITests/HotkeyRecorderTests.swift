import SwiftUI
import Testing
import UITestSupport

@testable import DesignSystem
@testable import SusurroUI

/// What the recorder of the hotkey paints and how it lays out, read from its pixels and its size, in light and dark.
@MainActor
@Suite("Hotkey recorder")
struct HotkeyRecorderTests {
    private let width: CGFloat = 560
    private var canvas: CGSize { CGSize(width: width, height: 220) }
    private var contentWidth: CGFloat { width - 2 * SnapshotSupport.margin() }

    private func recorder(_ state: HotkeyRecorderState) -> HotkeyRecorder {
        HotkeyRecorder(state: state, actions: .none)
    }

    private func picture(_ state: HotkeyRecorderState, scheme: ColorScheme = .light) -> CGImage {
        Probe.picture(of: recorder(state), size: canvas, scheme: scheme)
    }

    @Test("only a recorder that is listening has the accent outline around its field", arguments: Probe.schemes)
    func listeningIsOutlined(scheme: ColorScheme) throws {
        let accent = try Probe.theme(scheme).color(.accentPrimary)

        #expect(!Probe.isPainted(accent, in: picture(SettingsFixtures.recorderCustom, scheme: scheme)))
        #expect(Probe.isPainted(accent, in: picture(SettingsFixtures.recorderListening, scheme: scheme)))
    }

    @Test("the field fills the width it is given, less the Cancel button and the gap", arguments: Probe.schemes)
    func fieldFillsTheWidth(scheme: ColorScheme) throws {
        let accent = try Probe.theme(scheme).color(.accentPrimary)

        let outline = try #require(
            SnapshotSupport.extent(
                of: picture(SettingsFixtures.recorderListening, scheme: scheme), matching: accent,
                tolerance: Probe.exact))

        #expect(outline.minX < SnapshotSupport.margin() + 2, "\(outline)")
        #expect(outline.width > contentWidth - 140, "\(outline)")
        #expect(outline.width < contentWidth - 60, "\(outline)")
    }

    @Test("a refused shortcut is told in a banner in the warning color, and nothing is told otherwise")
    func rejectionIsTold() throws {
        for scheme in Probe.schemes {
            let warning = try Probe.theme(scheme).color(.statusWarning)

            #expect(!Probe.isPainted(warning, in: picture(SettingsFixtures.recorderListening, scheme: scheme)))
            #expect(Probe.isPainted(warning, in: picture(SettingsFixtures.recorderRefused, scheme: scheme)))
        }
    }

    @Test("the banner makes the recorder taller, and the field is still there under it")
    func rejectionAddsHeight() {
        let plain = Probe.height(of: recorder(SettingsFixtures.recorderListening), width: contentWidth)
        let refused = Probe.height(of: recorder(SettingsFixtures.recorderRefused), width: contentWidth)

        #expect(refused > plain + 30, "\(refused) against \(plain)")
    }

    @Test("the prompt shows until a modifier key is held, and then the key caps take its place")
    func heldKeysReplaceThePrompt() throws {
        for scheme in Probe.schemes {
            let prompt = try Probe.theme(scheme).color(.textSecondary)
            let waiting = picture(SettingsFixtures.recorderListening, scheme: scheme)
            let holding = picture(SettingsFixtures.recorderHolding, scheme: scheme)

            #expect(Probe.isPainted(prompt, in: waiting), "the prompt is in \(scheme)")
            #expect(!Probe.isPainted(prompt, in: holding), "the prompt is gone in \(scheme)")
            #expect(SnapshotSupport.differingPixels(waiting, holding, tolerance: Probe.exact) > 200)
        }
    }

    @Test("the field is as tall with the prompt as with the keys, so it does not jump when the first key is pressed")
    func fieldKeepsItsHeight() {
        let waiting = Probe.height(of: recorder(SettingsFixtures.recorderListening), width: contentWidth)
        let holding = Probe.height(of: recorder(SettingsFixtures.recorderHolding), width: contentWidth)

        #expect(waiting == holding, "\(waiting) against \(holding)")
    }

    @Test("the Restore default button is there only when the shortcut is not the default one")
    func restoreButton() throws {
        let raised = try Probe.theme(.light).color(.surfaceRaised)

        let idle = try #require(
            SnapshotSupport.extent(
                of: picture(SettingsFixtures.recorderIdle), matching: raised, tolerance: Probe.exact))
        let custom = try #require(
            SnapshotSupport.extent(
                of: picture(SettingsFixtures.recorderCustom), matching: raised, tolerance: Probe.exact))

        #expect(custom.width > idle.width + 100, "\(custom) against \(idle)")
        #expect(abs(custom.height - idle.height) <= 1)
    }

    @Test("the gap between the buttons is the md space, which is also the padding on each side of a button")
    func gapFollowsTheTheme() throws {
        func painted(_ theme: Theme) throws -> CGRect {
            let raised = try Probe.theme(.light, of: theme).color(.surfaceRaised)
            let image = Probe.picture(
                of: recorder(SettingsFixtures.recorderCustom), size: canvas, scheme: .light, theme: theme)
            return try #require(SnapshotSupport.extent(of: image, matching: raised, tolerance: Probe.exact))
        }

        let widened = try painted(Probe.spaced(.md, 30)).width - painted(.default).width

        // 12 points become 30: once for the gap, and twice for each of the two buttons, which pad both sides with md.
        #expect(abs(widened - (1 + 2 * 2) * (30 - 12)) <= 3, "\(widened)")
    }
}
