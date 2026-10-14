/// An app that was running when something was captured.
public struct AppIdentity: Sendable, Equatable {
    public let processID: Int32
    public let name: String
    public let bundleID: String?

    public init(processID: Int32, name: String, bundleID: String?) {
        self.processID = processID
        self.name = name
        self.bundleID = bundleID
    }
}

/// The app in front. It is read when a dictation starts, so the text goes only to the app it was dictated in.
@MainActor
public protocol FrontmostAppProvider: Sendable {
    func current() -> AppIdentity?
}
