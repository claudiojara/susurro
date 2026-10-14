import Domain
import Testing

@testable import TextShaping

@Suite("Style resolver")
struct StyleResolverTests {
    private let resolver = StyleResolver()

    private static let safari = "com.apple.Safari"

    private func resolve(
        _ bundleID: String?, url: String? = nil, settings: StyleSettings = .default
    ) -> StyleProfile {
        resolver.resolve(bundleID: bundleID, url: url, settings: settings)
    }

    // MARK: Categories and tones

    @Test("identical inputs give equal results")
    func deterministic() {
        let settings = StyleSettings(
            tones: [.email: .casual], overrides: [.bundle("com.apple.mail"): StyleOverride(tone: .verbatim)])

        let first = resolve("com.apple.mail", url: "https://mail.google.com", settings: settings)
        let second = resolve("com.apple.mail", url: "https://mail.google.com", settings: settings)

        #expect(first == second)
    }

    @Test(
        "every category has the default tone of the table",
        arguments: [
            (AppCategory.email, Tone.formal), (.workChat, .casual), (.personalMessaging, .veryCasual),
            (.document, .neutral), (.terminal, .verbatim), (.aiChat, .neutral), (.other, .neutral),
        ])
    func defaultTones(category: AppCategory, tone: Tone) {
        #expect(category.defaultTone == tone)
    }

    // MARK: Seeds (6a.2)

    @Test(
        "the seeds resolve to their categories",
        arguments: [
            (Optional("com.apple.mail"), Optional<String>.none, AppCategory.email, StyleSource.bundle),
            ("com.tinyspeck.slackmacgap", nil, .workChat, .bundle),
            ("com.apple.MobileSMS", nil, .personalMessaging, .bundle),
            ("com.apple.Terminal", nil, .terminal, .bundle),
            ("com.googlecode.iterm2", nil, .terminal, .bundle),
            (safari, "https://chatgpt.com/c/123", .aiChat, .url),
            (safari, "https://claude.ai/new", .aiChat, .url),
            (safari, "https://mail.google.com/mail/u/0/#inbox", .email, .url),
        ])
    func seeds(bundleID: String?, url: String?, category: AppCategory, source: StyleSource) {
        let style = resolve(bundleID, url: url)

        #expect(style.category == category)
        #expect(style.source == source)
    }

    @Test("Mail, Slack, Terminal, and ChatGPT in a browser get formal, casual, verbatim, and neutral")
    func fourReferenceApps() {
        #expect(resolve("com.apple.mail").tone == .formal)
        #expect(resolve("com.tinyspeck.slackmacgap").tone == .casual)
        #expect(resolve("com.apple.Terminal").tone == .verbatim)
        #expect(resolve(Self.safari, url: "https://chatgpt.com").tone == .neutral)
    }

    @Test("an app or a host with no rule is other, neutral, and decided by the default")
    func unknown() {
        #expect(resolve("dev.example.unknown") == StyleProfile(category: .other, tone: .neutral, source: .default))
        #expect(resolve(nil) == StyleProfile(category: .other, tone: .neutral, source: .default))
        #expect(
            resolve(Self.safari, url: "https://example.org/page")
                == StyleProfile(category: .other, tone: .neutral, source: .default))
    }

    // MARK: Precedence (6a.1)

    @Test("the host of a page in a browser beats the bundle ID")
    func hostBeatsBundle() {
        let table = SeedTable(bundles: [Self.safari: .document], hosts: ["mail.google.com": .email])
        let sut = StyleResolver(seeds: table)

        let style = sut.resolve(bundleID: Self.safari, url: "https://mail.google.com/", settings: .default)

        #expect(style.category == .email)
        #expect(style.source == .url)
    }

    @Test("a browser on a page with no rule falls back to the bundle ID")
    func bundleWhenTheHostHasNoRule() {
        let table = SeedTable(bundles: [Self.safari: .document], hosts: ["mail.google.com": .email])
        let sut = StyleResolver(seeds: table)

        let style = sut.resolve(bundleID: Self.safari, url: "https://example.org", settings: .default)

        #expect(style.category == .document)
        #expect(style.source == .bundle)
    }

    @Test("the URL of an app that is not a browser is ignored")
    func urlOnlyForBrowsers() {
        let style = resolve("com.apple.Terminal", url: "https://chatgpt.com")

        #expect(style.category == .terminal)
        #expect(style.source == .bundle)
    }

    @Test("an override beats the host and the bundle ID, and the result says so")
    func overrideWins() {
        let settings = StyleSettings(overrides: [
            .bundle("com.tinyspeck.slackmacgap"): StyleOverride(category: .personalMessaging),
            .host("mail.google.com"): StyleOverride(category: .document),
        ])

        let slack = resolve("com.tinyspeck.slackmacgap", settings: settings)
        let gmail = resolve(Self.safari, url: "https://mail.google.com", settings: settings)

        #expect(slack == StyleProfile(category: .personalMessaging, tone: .veryCasual, source: .override))
        #expect(gmail == StyleProfile(category: .document, tone: .neutral, source: .override))
    }

    @Test("an override for the site beats one for the app")
    func hostOverrideBeatsBundleOverride() {
        let settings = StyleSettings(overrides: [
            .bundle(Self.safari): StyleOverride(category: .document),
            .host("claude.ai"): StyleOverride(category: .terminal),
        ])

        #expect(resolve(Self.safari, url: "https://claude.ai", settings: settings).category == .terminal)
        #expect(resolve(Self.safari, url: "https://example.org", settings: settings).category == .document)
    }

    // MARK: Matching (6a.1)

    @Test(
        "a bundle ID matches a rule by exact value or by prefix at a dot",
        arguments: [
            ("com.apple.Terminal", true), ("com.apple.Terminal.helper", true), ("com.apple.TerminalX", false),
            ("com.apple", false), ("com.apple.terminal", false),
        ])
    func bundleMatching(bundleID: String, matches: Bool) {
        let style = resolve(bundleID)

        #expect((style.category == .terminal) == matches)
    }

    @Test(
        "a host matches case-insensitively with www. stripped, and subdomains match",
        arguments: [
            ("https://slack.com", true), ("https://app.slack.com/client", true), ("https://WWW.Slack.COM", true),
            ("https://www.app.slack.com", true), ("https://notslack.com", false), ("https://slack.com.evil.org", false),
            ("app.slack.com/client", true),
        ])
    func hostMatching(url: String, matches: Bool) {
        let style = resolve(Self.safari, url: url)

        #expect((style.category == .workChat) == matches)
    }

    @Test("the most specific rule wins")
    func longestRuleWins() {
        let table = SeedTable(
            bundles: ["com.example": .document, "com.example.chat": .workChat],
            hosts: ["example.org": .document, "chat.example.org": .workChat])
        let sut = StyleResolver(seeds: table)

        #expect(sut.resolve(bundleID: "com.example.chat.helper", url: nil).category == .workChat)
        #expect(sut.resolve(bundleID: "com.example.other", url: nil).category == .document)
        #expect(sut.resolve(bundleID: Self.safari, url: "https://x.chat.example.org").category == .workChat)
    }

    // MARK: User settings (6a.3)

    @Test("a tone-only override keeps the category of the seeds: Notes becomes document and casual")
    func toneOnlyOverride() {
        let settings = StyleSettings(overrides: [.bundle("com.apple.Notes"): StyleOverride(tone: .casual)])

        #expect(
            resolve("com.apple.Notes", settings: settings)
                == StyleProfile(category: .document, tone: .casual, source: .override))
    }

    @Test("a category-only override takes the tone of the new category")
    func categoryOnlyOverride() {
        let settings = StyleSettings(overrides: [.bundle("com.apple.Notes"): StyleOverride(category: .email)])

        #expect(resolve("com.apple.Notes", settings: settings).tone == .formal)
    }

    @Test("an override of both sets both")
    func bothOverride() {
        let settings = StyleSettings(overrides: [
            .bundle("com.apple.Notes"): StyleOverride(category: .terminal, tone: .casual)
        ])

        #expect(
            resolve("com.apple.Notes", settings: settings)
                == StyleProfile(category: .terminal, tone: .casual, source: .override))
    }

    @Test("an override that sets nothing decides nothing")
    func emptyOverride() {
        let settings = StyleSettings(overrides: [.bundle("com.apple.Notes"): StyleOverride()])

        #expect(resolve("com.apple.Notes", settings: settings).source == .bundle)
    }

    @Test("the tone the user chose for a category applies to every app in it")
    func editedToneTable() {
        let settings = StyleSettings(tones: [.email: .casual])

        #expect(resolve("com.apple.mail", settings: settings).tone == .casual)
        #expect(resolve(Self.safari, url: "https://mail.google.com", settings: settings).tone == .casual)
        #expect(resolve("com.apple.Terminal", settings: settings).tone == .verbatim)
    }

    // MARK: Candidate targets

    @Test("the targets of an override that could apply are the host chain of a browser page and the bundle chain")
    func candidateTargets() {
        let targets = resolver.candidateTargets(bundleID: Self.safari, url: "https://www.app.slack.com/x")

        #expect(
            targets == [
                .host("app.slack.com"), .host("slack.com"),
                .bundle("com.apple.Safari"), .bundle("com.apple"),
            ])
    }

    @Test("an app that is not a browser has no host among its targets")
    func candidateTargetsOfAnApp() {
        let targets = resolver.candidateTargets(bundleID: "com.apple.Notes", url: "https://slack.com")

        #expect(targets == [.bundle("com.apple.Notes"), .bundle("com.apple")])
    }
}
