import Testing

@testable import DesignSystem

@Suite("Theme resolution")
struct ThemeResolutionTests {
    private let day = RGBAColor(red: 0.1, green: 0.2, blue: 0.3)
    private let night = RGBAColor(red: 0.7, green: 0.8, blue: 0.9)

    @Test("a color resolves to its light value in light appearance and its dark value in dark")
    func colorFollowsAppearance() throws {
        var theme = Theme.default
        theme.palette["testInk"] = PaletteColor(light: day, dark: night)
        theme.colors["text.primary"] = "testInk"
        #expect(try theme.resolved(for: .light).color(.textPrimary) == day)
        #expect(try theme.resolved(for: .dark).color(.textPrimary) == night)
    }

    @Test("an appearance change re-resolves every color")
    func everyColorReResolves() throws {
        let theme = Theme.default
        let light = try theme.resolved(for: .light)
        let dark = try theme.resolved(for: .dark)
        #expect(light.appearance == .light)
        #expect(dark.appearance == .dark)
        for token in ColorToken.allCases {
            let entry = try #require(theme.colors[token.rawValue].flatMap { theme.palette[$0] })
            #expect(light.color(token) == entry.light, "\(token.rawValue) in light")
            #expect(dark.color(token) == entry.dark, "\(token.rawValue) in dark")
        }
        #expect(light != dark)
    }

    @Test("everything but color is the same in both appearances")
    func otherTokensIgnoreAppearance() throws {
        let theme = Theme.default
        for appearance in [Appearance.light, .dark] {
            let resolved = try theme.resolved(for: appearance)
            for token in SpacingToken.allCases { #expect(resolved.spacing(token) == theme.spacing[token.rawValue]) }
            for token in RadiusToken.allCases { #expect(resolved.radius(token) == theme.radii[token.rawValue]) }
            for token in MotionToken.allCases { #expect(resolved.motion(token) == theme.motion[token.rawValue]) }
            for token in TypeToken.allCases { #expect(resolved.type(token) == theme.typography[token.rawValue]) }
            #expect(resolved.overlay == theme.overlay)
            #expect(resolved.name == theme.name)
        }
    }

    @Test("a color that points at a missing palette entry is an error, and every such color is reported")
    func danglingReference() {
        var theme = Theme.default
        theme.colors["status.error"] = "nowhere"
        theme.colors["accent.primary"] = "nowhere"
        let expected: [ThemeError] = [
            .missingPaletteKey(token: "accent.primary", paletteKey: "nowhere"),
            .missingPaletteKey(token: "status.error", paletteKey: "nowhere"),
        ]
        #expect(theme.problems() == expected)
        #expect(throws: expected[0]) { try theme.resolved(for: .dark) }
    }

    @Test("a token the theme lacks is an error, reported before the dangling colors")
    func missingToken() {
        var theme = Theme.default
        theme.spacing["md"] = nil
        theme.colors["text.primary"] = nil
        #expect(theme.problems() == [.missingToken("colors.text.primary"), .missingToken("spacing.md")])
        theme.colors["status.error"] = "nowhere"
        #expect(theme.problems().last == .missingPaletteKey(token: "status.error", paletteKey: "nowhere"))
        #expect(throws: ThemeError.missingToken("colors.text.primary")) { try theme.resolved(for: .light) }
    }

    @Test("the bundled theme has no problems")
    func bundledThemeIsClean() {
        #expect(Theme.default.problems() == [])
    }

    @Test("errors read as one sentence that names the token")
    func errorsDescribeThemselves() {
        #expect(ThemeError.missingToken("spacing.md").description == "The theme does not define spacing.md.")
        #expect(
            ThemeError.missingPaletteKey(token: "accent.primary", paletteKey: "nowhere").description
                == "colors.accent.primary points at the palette entry \"nowhere\", which does not exist.")
    }
}
