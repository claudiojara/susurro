import AppKit
import SwiftUI

/// Puts the indicator in the panel and the panel on the main screen. This is the AppKit glue: everything it decides is
/// decided by the presenter and the placement, which are tested.
@MainActor
public final class SkeletonOverlayController: OverlaySurface {
    private let panel = SkeletonOverlayPanel()
    private let host = NSHostingView(rootView: SkeletonIndicatorView(indicator: nil))
    private let visibleFrame: () -> CGRect

    public convenience init() {
        self.init(visibleFrame: { NSScreen.main?.visibleFrame ?? .zero })
    }

    /// - Parameter visibleFrame: The area of the screen the overlay lives in, without the menu bar and the Dock.
    init(visibleFrame: @escaping () -> CGRect) {
        self.visibleFrame = visibleFrame
        panel.contentView = host
    }

    var panelFrame: CGRect { panel.frame }
    var isPanelVisible: Bool { panel.isVisible }

    public func display(_ indicator: OverlayIndicator?) {
        guard let indicator else {
            panel.orderOut(nil)
            return
        }
        host.rootView = SkeletonIndicatorView(indicator: indicator)
        let size = host.fittingSize
        panel.setFrame(SkeletonOverlayPlacement.frame(size: size, in: visibleFrame()), display: true)
        // Never `makeKeyAndOrderFront`: the panel must not take focus from the app being dictated into.
        panel.orderFrontRegardless()
    }
}
