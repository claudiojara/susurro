import AppKit
import DesignSystem
import SusurroUI
import SwiftUI

/// Where the overlay's state ends up: a panel on the screen, a recorder in a test.
@MainActor
public protocol OverlaySurface {
    /// Shows the overlay for the state, or hides it when the state is hidden.
    func display(_ state: OverlayViewState)
}

/// What the overlay panel holds: the container over the view model, in the theme of the theme model. A change of the
/// theme, the state, the level or the style id redraws it, because the models are observable.
struct OverlayWindowContent: View {
    let model: OverlayViewModel
    let themes: ThemeModel
    let registry: OverlayStyleRegistry

    var body: some View {
        OverlayContainer(model: model, registry: registry)
            .themed(themes.theme)
    }
}

/// The overlay on the screen: the panel from the UI package, put on the screen of the focused window at the edge the
/// user or the theme chose. This is the AppKit glue: what it shows and where it goes are decided by the view model and
/// `OverlayPlacement`, which are tested.
@MainActor
public final class OverlayController: OverlaySurface {
    private let model: OverlayViewModel
    private let themes: ThemeModel
    private let registry: OverlayStyleRegistry
    private let host: OverlayPanelHost<OverlayWindowContent>
    private let screens: () -> [OverlayScreen]
    private let mainScreen: () -> OverlayScreen?
    private let focusedWindow: () -> CGRect?

    public convenience init(model: OverlayViewModel, themes: ThemeModel, registry: OverlayStyleRegistry) {
        self.init(
            model: model, themes: themes, registry: registry,
            screens: { NSScreen.screens.map { OverlayScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
            mainScreen: { NSScreen.main.map { OverlayScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
            focusedWindow: FrontmostWindow.frame)
    }

    /// - Parameters:
    ///   - screens: The screens, with the area of each that the menu bar and the Dock leave free.
    ///   - mainScreen: The screen to use when there is no focused window.
    ///   - focusedWindow: The frame of the window the user is working in, in the coordinates of AppKit, or nil.
    init(
        model: OverlayViewModel, themes: ThemeModel, registry: OverlayStyleRegistry,
        screens: @escaping () -> [OverlayScreen], mainScreen: @escaping () -> OverlayScreen?,
        focusedWindow: @escaping () -> CGRect?
    ) {
        self.model = model
        self.themes = themes
        self.screens = screens
        self.mainScreen = mainScreen
        self.focusedWindow = focusedWindow
        self.registry = registry
        host = OverlayPanelHost(content: OverlayWindowContent(model: model, themes: themes, registry: registry))
    }

    var panelFrame: CGRect { host.panel.frame }
    var isPanelVisible: Bool { host.isVisible }

    public func display(_ state: OverlayViewState) {
        guard !state.isHidden else { return host.hide() }
        let allScreens = screens()
        guard let main = mainScreen() ?? allScreens.first else { return host.hide() }
        // The content is set again so that its size is the one of this state, not the one of the state before.
        host.setContent(OverlayWindowContent(model: model, themes: themes, registry: registry))
        let frame = OverlayPlacement.frame(
            size: host.fittingSize, geometry: themes.theme.overlay, edgePreference: model.edgePreference,
            focusedWindow: focusedWindow(), screens: allScreens, main: main)
        host.present(at: frame)
    }
}

/// The window the user is working in, as the window server reports it. Its bounds are public information: reading them
/// needs no permission, unlike the title of the window.
enum FrontmostWindow {
    /// The frame, in the coordinates of AppKit, of the front window of the frontmost app, or nil when there is none.
    static func frame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication, let primary = NSScreen.screens.first else {
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list goes from the front window to the back one. Windows above the normal layer are menus and the like.
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                window[kCGWindowLayer as String] as? Int == 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }
            return OverlayPlacement.appKitRect(fromWindowServer: bounds, mainScreenHeight: primary.frame.height)
        }
        return nil
    }
}
