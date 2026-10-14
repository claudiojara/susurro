/// The browsers whose page URL the app reads. The URL of any other app is ignored, so a document path or a link in a
/// chat window never picks a style.
public struct BrowserCatalog: Sendable, Equatable {
    public let bundleIDs: Set<String>

    public init(bundleIDs: Set<String>) {
        self.bundleIDs = bundleIDs
    }

    public func isBrowser(_ bundleID: String?) -> Bool {
        bundleID.map(bundleIDs.contains) ?? false
    }

    public static let standard = BrowserCatalog(bundleIDs: [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
    ])
}
