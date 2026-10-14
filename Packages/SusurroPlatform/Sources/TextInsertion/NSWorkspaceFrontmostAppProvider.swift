import AppKit
import Domain

/// The app in front, as `NSWorkspace` reports it. The coordinator reads it as a dictation starts, so the text goes
/// only to the app it was dictated in.
@MainActor
public final class NSWorkspaceFrontmostAppProvider: FrontmostAppProvider {
    private let application: @MainActor () -> NSRunningApplication?

    public init(workspace: NSWorkspace = .shared) {
        application = { workspace.frontmostApplication }
    }

    init(application: @escaping @MainActor () -> NSRunningApplication?) {
        self.application = application
    }

    public func current() -> AppIdentity? {
        guard let app = application() else { return nil }
        return AppIdentity(
            processID: app.processIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier)
    }
}
