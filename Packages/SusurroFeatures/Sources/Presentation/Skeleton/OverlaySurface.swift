/// Where the presenter's indicator ends up: a window in the app, a recorder in a test.
@MainActor
public protocol OverlaySurface {
    /// Shows the indicator, or hides the overlay when it is nil.
    func display(_ indicator: OverlayIndicator?)
}
