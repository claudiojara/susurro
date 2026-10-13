import AppKit
import SwiftUI

/// Puts the indicator in the panel and the panel on the main screen. This is the AppKit glue: everything it decides is
/// decided by the presenter and the placement, which are tested.
@MainActor
public final class SkeletonOverlayController: OverlaySurface {
    private let panel = SkeletonOverlayPanel()
    private let host = NSHostingView(rootView: SkeletonIndicatorView(indicator: nil))

    public init() {
        panel.contentView = host
    }

    public func display(_ indicator: OverlayIndicator?) {
        guard let indicator else {
            panel.orderOut(nil)
            return
        }
        host.rootView = SkeletonIndicatorView(indicator: indicator)
        let size = host.fittingSize
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(SkeletonOverlayPlacement.frame(size: size, in: visibleFrame), display: true)
        // Never `makeKeyAndOrderFront`: the panel must not take focus from the app being dictated into.
        panel.orderFrontRegardless()
    }
}
