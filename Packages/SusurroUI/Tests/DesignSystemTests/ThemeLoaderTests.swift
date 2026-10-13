import Foundation
import Testing

@testable import DesignSystem

@Suite("Theme loader")
struct ThemeLoaderTests {
    private func load(_ json: String) -> ThemeLoadResult {
        ThemeLoader.load(data: Data(json.utf8))
    }

    private func color(_ hex: String) throws -> RGBAColor {
        try #require(RGBAColor(hex: hex))
    }

    // MARK: Valid files

    @Test("a file that overrides only the accent inherits everything else, with no error")
    func partialFile() throws {
        let result = load(
            """
            {"schemaVersion": 1,
             "palette": {"ocean": {"light": "#0077B6", "dark": "#48CAE4"}},
             "colors": {"accent.primary": "ocean"}}
            """)
        var expected = Theme.default
        expected.palette["ocean"] = PaletteColor(light: try color("#0077B6"), dark: try color("#48CAE4"))
        expected.colors["accent.primary"] = "ocean"
        #expect(result.theme == expected)
        #expect(result.errors == [])
        #expect(try result.theme.resolved(for: .dark).color(.accentPrimary) == (try color("#48CAE4")))
        #expect(
            try result.theme.resolved(for: .dark).color(.accentRecording)
                == (try Theme.default.resolved(for: .dark).color(.accentRecording)))
    }

    @Test("a file can change one field of a token and keep the others")
    func fieldLevelOverride() {
        let result = load(
            """
            {"schemaVersion": 1, "name": "Roomy",
             "typography": {"body": {"size": 14}}, "overlay": {"width": 420}, "spacing": {"md": 14}}
            """)
        var expected = Theme.default
        expected.name = "Roomy"
        expected.typography["body"]?.size = 14
        expected.overlay.width = 420
        expected.spacing["md"] = 14
        #expect(result.theme == expected)
        #expect(result.theme.typography["body"]?.weight == Theme.default.typography["body"]?.weight)
        #expect(result.errors == [])
    }

    @Test("a file with only a version is the default theme")
    func versionOnly() {
        let result = load(#"{"schemaVersion": 1}"#)
        #expect(result.theme == .default)
        #expect(result.errors == [])
    }

    // MARK: Files that cannot be used

    @Test("text that is not JSON returns the default theme and says why")
    func malformedJSON() throws {
        let result = load(#"{"schemaVersion": 1, "#)
        #expect(result.theme == .default)
        #expect(result.errors.count == 1)
        guard case .malformedJSON(let reason) = try #require(result.errors.first) else {
            Issue.record("expected malformedJSON, got \(result.errors)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test("JSON that is not an object is malformed")
    func notAnObject() {
        let result = load("[1, 2]")
        #expect(result.theme == .default)
        #expect(result.errors == [.malformedJSON("The top level must be an object.")])
    }

    @Test("a version this build does not read is reported alone, whatever else the file holds")
    func unsupportedVersion() {
        for text in [#"{"schemaVersion": 2}"#, #"{"schemaVersion": 2, "spacing": [1, 2]}"#] {
            let result = load(text)
            #expect(result.theme == .default)
            #expect(result.errors == [.unsupportedSchemaVersion(found: 2, supported: 1)])
        }
    }

    @Test(
        "a missing or mistyped version is reported with its path",
        arguments: [(#"{"palette": {}}"#, "is missing."), (#"{"schemaVersion": "1"}"#, "must be a whole number.")])
    func badVersion(text: String, expectedReason: String) {
        let result = load(text)
        #expect(result.theme == .default)
        #expect(result.errors == [.invalidValue(path: "schemaVersion", reason: expectedReason)])
    }

    @Test(
        "a malformed token value returns the default theme and names the value",
        arguments: [
            (##"{"palette": {"ocean": {"light": "#GG0000", "dark": "#000000"}}}"##, "palette.ocean.light"),
            (##"{"palette": {"ocean": {"light": "#000000"}}}"##, "palette.ocean.dark"),
            (#"{"spacing": {"md": "wide"}}"#, "spacing.md"),
            (#"{"overlay": {"edge": "left"}}"#, "overlay.edge"),
            (#"{"typography": {"body": {"weight": "heavy"}}}"#, "typography.body.weight"),
            (#"{"spacing": [1, 2]}"#, "spacing"),
        ])
    func malformedValue(body: String, expectedPath: String) {
        let result = load(#"{"schemaVersion": 1, "# + body.dropFirst())
        #expect(result.theme == .default)
        #expect(result.errors.count == 1)
        if case .invalidValue(let path, let reason) = result.errors.first {
            #expect(path == expectedPath)
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected invalidValue at \(expectedPath), got \(result.errors)")
        }
    }

    @Test("the reason for a bad color quotes it")
    func badColorReason() {
        let result = load(##"{"schemaVersion": 1, "palette": {"ocean": {"light": "#GG0000", "dark": "#000000"}}}"##)
        if case .invalidValue(_, let reason) = result.errors.first {
            #expect(reason.contains("#GG0000"))
        } else {
            Issue.record("expected invalidValue, got \(result.errors)")
        }
    }

    @Test("a token the catalog does not list is reported, so a typo is not silent")
    func unknownTokens() {
        let result = load(
            """
            {"schemaVersion": 1, "colours": {},
             "colors": {"acent.primary": "blue"}, "spacing": {"huge": 40}}
            """)
        #expect(result.theme == .default)
        #expect(
            result.errors == [
                .unknownToken("colors.acent.primary"), .unknownToken("colours"), .unknownToken("spacing.huge"),
            ])
    }

    @Test("a color that points at a missing palette entry returns the default theme")
    func danglingReference() {
        let result = load(#"{"schemaVersion": 1, "colors": {"accent.primary": "nowhere"}}"#)
        #expect(result.theme == .default)
        #expect(result.errors == [.missingPaletteKey(token: "accent.primary", paletteKey: "nowhere")])
    }

    @Test("every problem of a file is reported together")
    func problemsAddUp() {
        let result = load(#"{"schemaVersion": 1, "spacing": {"huge": 40}, "colors": {"accent.primary": "nowhere"}}"#)
        #expect(
            result.errors == [
                .unknownToken("spacing.huge"), .missingPaletteKey(token: "accent.primary", paletteKey: "nowhere"),
            ])
    }

    @Test("each error reads as one sentence that names what is wrong")
    func errorsDescribeThemselves() {
        let expected: [(ThemeError, String)] = [
            (.malformedJSON("Unterminated object."), "The file is not valid JSON: Unterminated object."),
            (
                .unsupportedSchemaVersion(found: 2, supported: 1),
                "The file uses schema version 2, and this build reads version 1."
            ),
            (
                .invalidValue(path: "spacing.md", reason: "Expected a number."),
                "spacing.md is not valid: Expected a number."
            ),
            (.unknownToken("spacing.huge"), "spacing.huge is not a token of the theme."),
            (.unreadable(file: "night.json", reason: "No such file."), "Cannot read night.json: No such file."),
        ]
        #expect(expected.map { $0.0.description } == expected.map { $0.1 })
    }

    // MARK: Files on disk

    @Test("a file on disk loads like the same text")
    func fileOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"schemaVersion": 1, "spacing": {"md": 14}}"#.utf8).write(to: url)
        let result = ThemeLoader.load(contentsOf: url)
        #expect(result.theme.spacing["md"] == 14)
        #expect(result.errors == [])
    }

    @Test("a file that cannot be read returns the default theme and names the file")
    func unreadableFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let result = ThemeLoader.load(contentsOf: url)
        #expect(result.theme == .default)
        #expect(result.errors.count == 1)
        if case .unreadable(let file, let reason) = result.errors.first {
            #expect(file == url.lastPathComponent)
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected unreadable, got \(result.errors)")
        }
    }
}
