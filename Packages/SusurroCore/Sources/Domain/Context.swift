/// The app a dictation goes to, as the frontmost-app lookup reports it.
///
/// Provisional: the context-capture track (6b.3) owns this file. The OCR gating reads the identity only to tell whether
/// the frontmost app or window changed.
public struct AppIdentity: Sendable, Equatable {
    public let processID: Int32
    public let name: String
    public let bundleID: String
    public let windowTitle: String?

    public init(processID: Int32, name: String, bundleID: String, windowTitle: String? = nil) {
        self.processID = processID
        self.name = name
        self.bundleID = bundleID
        self.windowTitle = windowTitle
    }
}
