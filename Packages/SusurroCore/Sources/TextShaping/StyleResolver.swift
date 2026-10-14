import Domain

/// Chooses the category and tone for the app the user is dictating into. It is pure: the same inputs give the same
/// result. The rules apply in this order, and the result says which one decided:
///
/// 1. the user's override for the site, when the app is a browser showing it, and then for the app;
/// 2. the host of the page, when the app is a browser;
/// 3. the bundle ID of the app;
/// 4. `other`.
///
/// An override can set the category, the tone, or both. What it leaves out comes from the other rules, so an override
/// that only sets the tone keeps the category the seeds give.
public struct StyleResolver: Sendable {
    private let seeds: SeedTable
    private let browsers: BrowserCatalog

    public init(seeds: SeedTable = .standard, browsers: BrowserCatalog = .standard) {
        self.seeds = seeds
        self.browsers = browsers
    }

    /// - Parameters:
    ///   - bundleID: The ID of the app in front.
    ///   - url: The address of the page, for a browser. It is ignored for any other app.
    public func resolve(bundleID: String?, url: String?, settings: StyleSettings = .default) -> StyleProfile {
        let host = browsers.isBrowser(bundleID) ? url.flatMap(StyleMatching.host(ofURL:)) : nil
        let override = override(bundleID: bundleID, host: host, in: settings.overrides)
        let seeded = seededCategory(bundleID: bundleID, host: host)
        let category = override?.category ?? seeded.category
        let tone = override?.tone ?? settings.tones[category] ?? category.defaultTone
        return StyleProfile(category: category, tone: tone, source: override == nil ? seeded.source : .override)
    }

    /// The targets under which the user could have stored an override that applies to this app and page: the host and its
    /// parent domains for a browser, and the bundle ID and the IDs above it. A store that is read by key looks up these.
    public func candidateTargets(bundleID: String?, url: String?) -> [StyleTarget] {
        let host = browsers.isBrowser(bundleID) ? url.flatMap(StyleMatching.host(ofURL:)) : nil
        let hosts = host.map(StyleMatching.hostChain) ?? []
        let bundles = bundleID.map(StyleMatching.bundleChain) ?? []
        return hosts.map(StyleTarget.host) + bundles.map(StyleTarget.bundle)
    }

    private func seededCategory(bundleID: String?, host: String?) -> (category: AppCategory, source: StyleSource) {
        if let host,
            let match = StyleMatching.longest(in: seeds.hosts, where: { StyleMatching.host(host, matches: $0) })
        {
            return (match.value, .url)
        }
        if let bundleID,
            let match = StyleMatching.longest(
                in: seeds.bundles, where: { StyleMatching.bundleID(bundleID, matches: $0) })
        {
            return (match.value, .bundle)
        }
        return (.other, .default)
    }

    /// The override that applies. One for the site beats one for the app, and the most specific rule of each wins.
    private func override(
        bundleID: String?, host: String?, in overrides: [StyleTarget: StyleOverride]
    ) -> StyleOverride? {
        var hostRules: [String: StyleOverride] = [:]
        var bundleRules: [String: StyleOverride] = [:]
        for (target, override) in overrides where !override.isEmpty {
            switch target {
            case .host(let rule): hostRules[rule] = override
            case .bundle(let rule): bundleRules[rule] = override
            }
        }
        if let host, let match = StyleMatching.longest(in: hostRules, where: { StyleMatching.host(host, matches: $0) })
        {
            return match.value
        }
        if let bundleID,
            let match = StyleMatching.longest(in: bundleRules, where: { StyleMatching.bundleID(bundleID, matches: $0) })
        {
            return match.value
        }
        return nil
    }
}
