import CoreGraphics
import Domain
import ScreenCaptureKit

/// Takes a picture of a window with ScreenCaptureKit. It needs the Screen Recording permission, which the OCR setting
/// asks for, and it is covered by the manual check, not by tests.
public struct ScreenCaptureWindowImageProvider: WindowImageProviding {
    /// The longest side of the picture, in pixels. Text on a screen reads well at this size, and a larger picture only
    /// costs time.
    private static let longestSide = 2_400.0

    public init() {}

    public func windowImage(of app: AppIdentity) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter {
            $0.owningApplication?.processID == app.processID && $0.windowLayer == 0 && $0.frame.width > 1
        }
        guard let window = windows.first(where: { $0.title == app.windowTitle }) ?? windows.first else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(2.0, Self.longestSide / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
