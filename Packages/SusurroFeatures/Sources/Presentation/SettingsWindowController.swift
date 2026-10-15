import AppKit
import DesignSystem
import SusurroUI
import SwiftUI

/// What the settings window holds: the container over the view model, in the theme and the appearance of the theme model.
/// A change of either redraws it, because the theme model is observable.
struct SettingsWindowContent: View {
    let model: SettingsViewModel
    let themes: ThemeModel
    let recorder: AnyView
    var pasteLastRecorder = AnyView(EmptyView())
    var hotkeyCards = AnyView(EmptyView())

    var body: some View {
        SettingsContainer(model: model, pasteLastRecorder: pasteLastRecorder, hotkeyCards: hotkeyCards) { recorder }
            .themed(themes.theme, override: themes.appearance)
    }
}

/// The window of the settings: a titled window that can be closed, as wide and as tall as the theme says. This is the
/// AppKit glue: what it shows is decided by the screen, which is tested.
@MainActor
public final class SettingsWindowController: SettingsSurface {
    let window: NSWindow
    private let host: NSHostingController<SettingsWindowContent>
    private let activate: @MainActor () -> Void
    private var hasBeenPlaced = false

    /// - Parameters:
    ///   - recorder: The control that changes the hotkey, which the app builds over the keys of the platform, a package
    ///     the UI package cannot import.
    ///   - pasteLastRecorder: The control that changes the paste last dictation shortcut, built the same way.
    ///   - hotkeyCards: The cards the Hotkey tab shows below the dictation hotkey, such as command mode.
    public convenience init(
        model: SettingsViewModel, themes: ThemeModel, recorder: AnyView = AnyView(EmptyView()),
        pasteLastRecorder: AnyView = AnyView(EmptyView()), hotkeyCards: AnyView = AnyView(EmptyView())
    ) {
        self.init(
            model: model, themes: themes, recorder: recorder, pasteLastRecorder: pasteLastRecorder,
            hotkeyCards: hotkeyCards, activate: { NSApplication.shared.activate() })
    }

    /// - Parameter activate: Brings the app forward. Tests pass a recorder, since a test process is no app to bring.
    init(
        model: SettingsViewModel, themes: ThemeModel, recorder: AnyView,
        pasteLastRecorder: AnyView = AnyView(EmptyView()), hotkeyCards: AnyView = AnyView(EmptyView()),
        activate: @escaping @MainActor () -> Void
    ) {
        self.activate = activate
        host = NSHostingController(
            rootView: SettingsWindowContent(
                model: model, themes: themes, recorder: recorder, pasteLastRecorder: pasteLastRecorder,
                hotkeyCards: hotkeyCards))
        host.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: host)
        let window = window
        followLanguage { window.title = SettingsCopy.windowTitle }
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
    }

    public func show() {
        if !hasBeenPlaced {
            window.setContentSize(host.view.fittingSize)
            window.center()
            hasBeenPlaced = true
        }
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}
