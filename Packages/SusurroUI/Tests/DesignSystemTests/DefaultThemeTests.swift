import Testing

@testable import DesignSystem

@Suite("Default theme")
struct DefaultThemeTests {
    private let theme = Theme.default

    @Test("the catalog lists the tokens of every kind")
    func catalogCoversEveryKind() {
        let expected =
            ColorToken.allCases.count + TypeToken.allCases.count + SpacingToken.allCases.count
            + RadiusToken.allCases.count + MotionToken.allCases.count + OverlayGeometry.CodingKeys.allCases.count
        #expect(expected > 0)
        #expect(ThemeTokenCatalog.allKeys.count == expected)
        #expect(ThemeTokenCatalog.allKeys.contains("colors.text.primary"))
        #expect(ThemeTokenCatalog.allKeys.contains("overlay.cornerRadius"))
    }

    @Test("the bundled theme defines every token in the catalog")
    func definesEveryCatalogToken() {
        #expect(ThemeTokenCatalog.missingKeys(in: theme) == [])
    }

    @Test("the catalog names each token the bundled theme lacks")
    func listsMissingTokens() {
        var incomplete = theme
        incomplete.spacing["md"] = nil
        incomplete.colors["text.primary"] = nil
        incomplete.typography["body"] = nil
        #expect(
            ThemeTokenCatalog.missingKeys(in: incomplete) == ["colors.text.primary", "spacing.md", "typography.body"])
    }

    @Test("the bundled theme defines nothing the catalog does not list")
    func definesNoOtherToken() {
        #expect(ThemeTokenCatalog.definedKeys(in: theme) == ThemeTokenCatalog.allKeys)
    }

    @Test("every color token points at a palette entry with a light and a dark value")
    func colorsHaveBothAppearances() throws {
        for token in ColorToken.allCases {
            let name = try #require(theme.colors[token.rawValue], "\(token.rawValue) has no palette entry")
            #expect(theme.palette[name] != nil, "\(token.rawValue) points at \(name), which is not in the palette")
        }
        let differing = theme.palette.values.filter { $0.light != $0.dark }
        #expect(differing.count > 1, "dark values are copies of the light ones")
    }

    @Test("the scales grow from one step to the next")
    func scalesGrow() throws {
        func values<T: ThemeToken>(_ table: [String: Double], _ tokens: [T]) throws -> [Double] {
            try tokens.map { try #require(table[$0.rawValue]) }
        }
        let spacing = try values(theme.spacing, [SpacingToken.xs, .sm, .md, .lg, .xl])
        let radii = try values(theme.radii, [RadiusToken.sm, .md, .lg])
        let durations = try values(theme.motion, [MotionToken.fast, .standard, .slow])
        for scale in [spacing, radii, durations] {
            #expect(scale.first.map { $0 > 0 } == true)
            #expect(scale == scale.sorted())
            #expect(Set(scale).count == scale.count)
        }
    }

    @Test("type sizes grow from caption to title")
    func typeSizesGrow() throws {
        let roles: [TypeToken] = [.caption, .body, .headline, .title]
        let sizes = try roles.map { try #require(theme.typography[$0.rawValue]).size }
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count == sizes.count)
    }

    @Test("the theme carries the schema version this build reads")
    func schemaVersion() {
        #expect(theme.schemaVersion == Theme.supportedSchemaVersion)
        #expect(!theme.name.isEmpty)
    }
}
