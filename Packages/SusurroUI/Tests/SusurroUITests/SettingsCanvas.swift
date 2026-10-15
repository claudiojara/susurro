import SwiftUI
import Testing
import UITestSupport

@testable import SusurroUI

/// The canvas each settings view is drawn on for its snapshot, written down and not measured, so a canvas that followed
/// the fonts of the machine cannot give a picture of another size on another macOS (`SettingsCanvasTests` keeps the
/// sizes from drifting away from the views). Text inputs are drawn as plain text: the system text field is a native
/// control that the renderer cannot draw.
enum SettingsCanvas: CaseIterable, Sendable, CustomTestStringConvertible {
    case shortcutKeyed, shortcutFn
    case rowParakeet, rowLocalWhisper, rowLocalWhisperInvalid, rowDeepgramNeedsKey, rowAnthropic, rowOpenAICompatible
    case general, generalPinned
    case providers
    case hotkey, hotkeyWarnings, hotkeyRecording
    case commandMode, commandModeUnavailable
    case recorderIdle, recorderCustom, recorderListening, recorderHolding, recorderRefused
    case styleSeeds, styleOverrides
    case dictionaryEmpty, dictionaryPopulated
    case replacementsEmpty, replacementsPopulated, snippetsEmpty, snippetsPopulated, fillers
    case appearance
    case audio, audioMissing
    case pasteLast, pasteLastUnassigned
    case screenGeneral

    var testDescription: String { "\(self)" }

    /// The width of a section inside the settings window: the window, less the padding on both sides.
    private static let sectionWidth: CGFloat = 584

    var size: CGSize {
        switch self {
        case .shortcutKeyed: CGSize(width: 160, height: 64)
        case .shortcutFn: CGSize(width: 160, height: 64)
        case .rowParakeet: CGSize(width: Self.sectionWidth, height: 120)
        case .rowLocalWhisper: CGSize(width: Self.sectionWidth, height: 308)
        case .rowLocalWhisperInvalid: CGSize(width: Self.sectionWidth, height: 326)
        case .rowDeepgramNeedsKey: CGSize(width: Self.sectionWidth, height: 155)
        case .rowAnthropic: CGSize(width: Self.sectionWidth, height: 205)
        case .rowOpenAICompatible: CGSize(width: Self.sectionWidth, height: 273)
        case .general: CGSize(width: Self.sectionWidth, height: 664)
        case .generalPinned: CGSize(width: Self.sectionWidth, height: 690)
        case .providers: CGSize(width: Self.sectionWidth, height: 890)
        case .hotkey: CGSize(width: Self.sectionWidth, height: 158)
        case .hotkeyWarnings: CGSize(width: Self.sectionWidth, height: 334)
        case .hotkeyRecording: CGSize(width: Self.sectionWidth, height: 209)
        case .commandMode: CGSize(width: Self.sectionWidth, height: 244)
        case .commandModeUnavailable: CGSize(width: Self.sectionWidth, height: 268)
        case .recorderIdle: CGSize(width: Self.sectionWidth, height: 64)
        case .recorderCustom: CGSize(width: Self.sectionWidth, height: 64)
        case .recorderListening: CGSize(width: Self.sectionWidth, height: 79)
        case .recorderHolding: CGSize(width: Self.sectionWidth, height: 79)
        case .recorderRefused: CGSize(width: Self.sectionWidth, height: 147)
        case .styleSeeds: CGSize(width: Self.sectionWidth, height: 896)
        case .styleOverrides: CGSize(width: Self.sectionWidth, height: 988)
        case .dictionaryEmpty: CGSize(width: Self.sectionWidth, height: 195)
        case .dictionaryPopulated: CGSize(width: Self.sectionWidth, height: 301)
        case .replacementsEmpty: CGSize(width: Self.sectionWidth, height: 200)
        case .replacementsPopulated: CGSize(width: Self.sectionWidth, height: 260)
        case .snippetsEmpty: CGSize(width: Self.sectionWidth, height: 222)
        case .snippetsPopulated: CGSize(width: Self.sectionWidth, height: 338)
        case .fillers: CGSize(width: Self.sectionWidth, height: 150)
        case .appearance: CGSize(width: Self.sectionWidth, height: 236)
        case .audio: CGSize(width: Self.sectionWidth, height: 272)
        case .audioMissing: CGSize(width: Self.sectionWidth, height: 298)
        case .pasteLast: CGSize(width: Self.sectionWidth, height: 186)
        case .pasteLastUnassigned: CGSize(width: Self.sectionWidth, height: 179)
        case .screenGeneral: CGSize(width: 632, height: 512)
        }
    }

    @MainActor var view: AnyView {
        AnyView(content.environment(\.staticControls, true))
    }

    @MainActor private var content: AnyView {
        switch self {
        case .shortcutKeyed: AnyView(ShortcutBadge(["⌃", "⌥", "D"]))
        case .shortcutFn: AnyView(ShortcutBadge(["fn"]))
        case .rowParakeet: row(.parakeetReady)
        case .rowLocalWhisper: row(.localWhisperServer)
        case .rowLocalWhisperInvalid: row(.localWhisperInvalid)
        case .rowDeepgramNeedsKey: row(.deepgramNeedsKey)
        case .rowAnthropic: row(.anthropicReady)
        case .rowOpenAICompatible: row(.openAICompatible)
        case .general: AnyView(GeneralSection(SettingsFixtures.general, actions: .none))
        case .generalPinned: AnyView(GeneralSection(SettingsFixtures.generalPinned, actions: .none))
        case .providers: AnyView(ProvidersSection(SettingsFixtures.providers, actions: .none))
        case .hotkey: AnyView(HotkeySection(SettingsFixtures.hotkey, actions: .none) { EmptyView() })
        case .hotkeyWarnings: AnyView(HotkeySection(SettingsFixtures.hotkeyWarnings, actions: .none) { EmptyView() })
        case .hotkeyRecording:
            AnyView(
                HotkeySection(SettingsFixtures.hotkey, actions: .none) {
                    HotkeyRecorder(state: SettingsFixtures.recorderHolding, actions: .none)
                })
        case .commandMode:
            AnyView(
                CommandModeSection(SettingsFixtures.commandMode, actions: .none) {
                    HotkeyRecorder(state: SettingsFixtures.recorderIdle, actions: .none)
                })
        case .commandModeUnavailable:
            AnyView(CommandModeSection(SettingsFixtures.commandModeUnavailable, actions: .none) { EmptyView() })
        case .recorderIdle: recorder(SettingsFixtures.recorderIdle)
        case .recorderCustom: recorder(SettingsFixtures.recorderCustom)
        case .recorderListening: recorder(SettingsFixtures.recorderListening)
        case .recorderHolding: recorder(SettingsFixtures.recorderHolding)
        case .recorderRefused: recorder(SettingsFixtures.recorderRefused)
        case .styleSeeds: AnyView(StyleTableEditor(SettingsFixtures.style, actions: .none))
        case .styleOverrides: AnyView(StyleTableEditor(SettingsFixtures.styleWithOverrides, actions: .none))
        case .dictionaryEmpty: AnyView(DictionaryEditor(SettingsFixtures.dictionaryEmpty, actions: .none))
        case .dictionaryPopulated: AnyView(DictionaryEditor(SettingsFixtures.dictionary, actions: .none))
        case .replacementsEmpty: AnyView(ReplacementRulesEditor(SettingsFixtures.textRulesEmpty, actions: .none))
        case .replacementsPopulated: AnyView(ReplacementRulesEditor(SettingsFixtures.textRules, actions: .none))
        case .snippetsEmpty: AnyView(SnippetsEditor(SettingsFixtures.textRulesEmpty, actions: .none))
        case .snippetsPopulated: AnyView(SnippetsEditor(SettingsFixtures.textRules, actions: .none))
        case .fillers: AnyView(FillerRemovalCard(isOn: true) { _ in })
        case .appearance: AnyView(AppearanceSection(SettingsFixtures.appearance, actions: .none))
        case .audio: AnyView(AudioSection(SettingsFixtures.audio, actions: .none))
        case .audioMissing: AnyView(AudioSection(SettingsFixtures.audioMissing, actions: .none))
        case .pasteLast:
            AnyView(PasteLastSection(SettingsFixtures.pasteLast) { recorder(SettingsFixtures.recorderPasteLast) })
        case .pasteLastUnassigned:
            AnyView(PasteLastSection(SettingsFixtures.pasteLastUnassigned) { recorder(SettingsFixtures.recorderIdle) })
        case .screenGeneral:
            AnyView(SettingsScreen(state: SettingsFixtures.screen, actions: .none) { EmptyView() })
        }
    }

    @MainActor private func recorder(_ state: HotkeyRecorderState) -> AnyView {
        AnyView(HotkeyRecorder(state: state, actions: .none))
    }

    @MainActor private func row(_ fixture: SettingsFixtures.Row) -> AnyView {
        AnyView(ProviderRow(SettingsFixtures.row(fixture), onSelect: {}, onEnable: { _ in }, onField: { _, _ in }))
    }
}
