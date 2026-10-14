import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// One picture per view and appearance, each on a canvas just big enough for it (`SettingsCanvas`). The references are
/// recorded on the CI image (`record-snapshots`), never here, and `make test` skips these suites by their name.
@MainActor
@Suite("Settings snapshots")
struct SettingsSnapshotTests {
    nonisolated private static let shortcuts: [SettingsCanvas] = [.shortcutKeyed, .shortcutFn]
    nonisolated private static let rows: [SettingsCanvas] = [
        .rowParakeet, .rowLocalWhisper, .rowLocalWhisperInvalid, .rowDeepgramNeedsKey, .rowAnthropic,
        .rowOpenAICompatible,
    ]
    nonisolated private static let sections: [SettingsCanvas] = [
        .general, .generalPinned, .providers, .hotkey, .hotkeyWarnings, .hotkeyRecording, .appearance,
    ]
    nonisolated private static let recorders: [SettingsCanvas] = [
        .recorderIdle, .recorderCustom, .recorderListening, .recorderHolding, .recorderRefused,
    ]
    nonisolated private static let style: [SettingsCanvas] = [.styleSeeds, .styleOverrides]
    nonisolated private static let dictionary: [SettingsCanvas] = [.dictionaryEmpty, .dictionaryPopulated]
    nonisolated private static let screens: [SettingsCanvas] = [.screenGeneral]

    @Test("the shortcut badge for a keyed hotkey and for fn", arguments: shortcuts, Probe.schemes)
    func shortcuts(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("a provider row in each state", arguments: rows, Probe.schemes)
    func rows(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the General, Providers, Hotkey, and Appearance sections", arguments: sections, Probe.schemes)
    func sections(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the hotkey recorder at rest, listening, holding keys, and refusing one", arguments: recorders, Probe.schemes)
    func recorders(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the style table with the seeds only and with overrides", arguments: style, Probe.schemes)
    func style(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the dictionary editor, empty and with terms", arguments: dictionary, Probe.schemes)
    func dictionary(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }

    @Test("the settings screen", arguments: screens, Probe.schemes)
    func screens(canvas: SettingsCanvas, scheme: ColorScheme) {
        assertViewSnapshot(of: canvas.view, size: canvas.size, scheme: scheme, named: "\(canvas)-\(scheme.pictureName)")
    }
}
