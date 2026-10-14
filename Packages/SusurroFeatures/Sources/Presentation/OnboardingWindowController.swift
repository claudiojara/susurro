import AppKit
import DesignSystem
import SusurroUI
import SwiftUI

/// What the onboarding window holds: the container over the view model, in the theme of the theme model. A change of
/// the theme redraws it, because the theme model is observable.
struct OnboardingWindowContent: View {
    let model: OnboardingViewModel
    let themes: ThemeModel
    /// The most the screen may take, so that the window fits the display, or nil for no limit.
    var maxHeight: CGFloat?
    let onDone: () -> Void

    var body: some View {
        OnboardingContainer(model: model, maxHeight: maxHeight, onDone: onDone)
            .themed(themes.theme, override: themes.appearance)
    }
}

/// The window of the onboarding: a titled window that can be closed, as wide as the theme says, and as tall as the
/// screen is, which it follows when rows or troubleshooting steps come and go. On a display too short for the screen the
/// window is cut to the visible frame and the checklist scrolls (see `OnboardingScreen`). This is the AppKit glue: what it shows and
/// when it opens are decided by the screen and the presenter, which are tested.
@MainActor
public final class OnboardingWindowController: OnboardingSurface {
    let window: NSWindow
    private let host: NSHostingController<OnboardingWindowContent>
    private let activate: @MainActor () -> Void
    private let visibleFrame: () -> CGRect
    private var hasBeenPlaced = false

    public convenience init(model: OnboardingViewModel, themes: ThemeModel) {
        self.init(
            model: model, themes: themes, activate: { NSApplication.shared.activate() },
            visibleFrame: { NSScreen.main?.visibleFrame ?? .zero })
    }

    /// - Parameters:
    ///   - activate: Brings the app forward. Tests pass a recorder, since a test process is no app to bring.
    ///   - visibleFrame: The area of the screen the window opens in, without the menu bar and the Dock.
    init(
        model: OnboardingViewModel, themes: ThemeModel, activate: @escaping @MainActor () -> Void,
        visibleFrame: @escaping () -> CGRect
    ) {
        self.activate = activate
        self.visibleFrame = visibleFrame
        host = NSHostingController(
            rootView: OnboardingWindowContent(model: model, themes: themes, maxHeight: nil, onDone: {}))
        host.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: host)
        window.title = model.state.title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        host.rootView = OnboardingWindowContent(
            model: model, themes: themes, maxHeight: nil, onDone: { [weak self] in self?.close() })
    }

    var content: OnboardingWindowContent { host.rootView }

    public func show() {
        placeIfNeeded()
        activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Cuts the content to the display, and places the window the first time, leaving it where the user put it after
    /// that. The window has the size of its content before it is placed, so that it is centered by the size it will have
    /// and not by the one it has before its first layout.
    func placeIfNeeded() {
        capToDisplay()
        guard !hasBeenPlaced else { return }
        window.setContentSize(host.view.fittingSize)
        window.setFrameOrigin(Self.origin(of: window.frame.size, in: visibleFrame()))
        hasBeenPlaced = true
    }

    func close() {
        window.close()
    }

    /// Limits the screen to what fits the display it opens on: the visible frame less the title bar, which is the most the
    /// content may be for the whole window to fit. A display that is not known leaves the screen as tall as it is.
    private func capToDisplay() {
        let area = visibleFrame()
        let probe = CGRect(x: 0, y: 0, width: 100, height: 100)
        let titleBar = NSWindow.frameRect(forContentRect: probe, styleMask: window.styleMask).height - probe.height
        let cap = area.height > titleBar ? area.height - titleBar : nil
        guard cap != host.rootView.maxHeight else { return }
        var content = host.rootView
        content.maxHeight = cap
        host.rootView = content
    }

    /// Where the lower left corner of a window of `size` goes in `area`: centered across it, with a third of the room left
    /// over above it and two thirds below, which is where the eye looks first. A window taller than the area has its
    /// top at the top of the area.
    static func origin(of size: CGSize, in area: CGRect) -> CGPoint {
        let spare = (area.height - size.height) / 3
        let top = min(area.maxY, area.maxY - spare)
        return CGPoint(x: area.midX - size.width / 2, y: top - size.height)
    }
}
