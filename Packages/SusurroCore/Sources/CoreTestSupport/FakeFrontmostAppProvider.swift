import Domain

/// A frontmost app that a test sets, and that logs how often it was read.
@MainActor
public final class FakeFrontmostAppProvider: FrontmostAppProvider {
    public var app: AppIdentity?
    public private(set) var reads = 0

    public init(_ app: AppIdentity? = nil) {
        self.app = app
    }

    public func current() -> AppIdentity? {
        reads += 1
        return app
    }
}

extension AppIdentity {
    /// Mail, as the tests' stand-in for the app a dictation starts in.
    public static let mail = AppIdentity(processID: 100, name: "Mail", bundleID: "com.apple.mail")
    /// Slack, as the tests' stand-in for another app.
    public static let slack = AppIdentity(processID: 200, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
}
