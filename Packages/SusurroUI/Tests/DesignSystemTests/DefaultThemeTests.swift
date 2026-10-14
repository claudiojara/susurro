import Foundation
import Testing

@testable import DesignSystem

@Suite("Default theme")
struct DefaultThemeTests {
    private let theme = Theme.default

    @Test("the catalog lists the tokens of every kind")
    func catalogCoversEveryKind() {
        let expected =
            ColorToken.allCases.count + TypeToken.allCases.count + SpacingToken.allCases.count
            + RadiusToken.allCases.count + SizeToken.allCases.count + LayoutToken.allCases.count
            + MotionToken.allCases.count
            + OverlayGeometry.CodingKeys.allCases.count
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

    @Test("each token group is a property of Theme, a key of the file, and a table that holds its tokens")
    func groupsMatchTheThemeAndTheFile() throws {
        let encoded = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(theme)) as? [String: Any])
        let bundled = Theme.bundledObject
        #expect(ThemeTokenCatalog.groups.count == 8)
        for group in ThemeTokenCatalog.groups {
            let property = try #require(
                encoded[group.name] as? [String: Any], "\(group.name) is not a property of Theme")
            #expect(
                Set(property.keys) == group.defined(theme), "\(group.name): Theme and the group read different names")
            let file = try #require(bundled[group.name] as? [String: Any], "\(group.name) is not in DefaultTheme.json")
            #expect(Set(file.keys) == group.expected, "\(group.name): the file and the token cases differ")
        }
        #expect(
            ThemeTokenCatalog.groups.map(\.name)
                == ["colors", "typography", "spacing", "radii", "sizes", "layout", "motion", "overlay"])
    }

    @Test("the sizes are the dimensions of components, and the geometry of a screen is in the layout group")
    func sizesAndLayoutAreApart() {
        #expect(SizeToken.allCases.map(\.rawValue) == ["statusDot", "levelBar"])
        #expect(LayoutToken.allCases.map(\.rawValue) == ["onboardingWidth", "settingsWidth", "settingsHeight"])
        #expect(theme.layout["onboardingWidth"] == 440)
        #expect(theme.sizes["onboardingWidth"] == nil)
        #expect(LayoutToken.group == "layout")
    }

    @Test("the pending color is a role of its own, not the accent: a waiting row cannot be taken for a primary button")
    func pendingIsNotTheAccent() throws {
        let pending = try #require(theme.colors[ColorToken.statusPending.rawValue].flatMap { theme.palette[$0] })
        let accent = try #require(theme.colors[ColorToken.accentPrimary.rawValue].flatMap { theme.palette[$0] })

        #expect(ColorToken.statusPending.rawValue == "status.pending")
        #expect(pending.light != accent.light)
        #expect(pending.dark != accent.dark)
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

    @Test("the scales grow from one step to the next, in the order the token cases are declared")
    func scalesGrow() throws {
        func values<T: ThemeToken>(_ table: [String: Double], _ tokens: [T]) throws -> [Double] {
            try tokens.map { try #require(table[$0.rawValue]) }
        }
        let spacing = try values(theme.spacing, SpacingToken.allCases)
        let radii = try values(theme.radii, RadiusToken.allCases)
        let durations = try values(theme.motion, DurationToken.allCases.map(\.token))
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
