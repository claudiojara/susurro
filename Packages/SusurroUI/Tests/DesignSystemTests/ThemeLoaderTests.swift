import Foundation
import Testing

@testable import DesignSystem

@Suite("Theme loader")
struct ThemeLoaderTests {
    private func load(_ json: String) -> ThemeLoadResult {
        ThemeLoader.load(data: Data(json.utf8))
    }

    /// `body` is a JSON object holding the keys to add to a file that has the right version.
    private func load(adding body: String) -> ThemeLoadResult {
        load(#"{"schemaVersion": 1, "# + body.dropFirst())
    }

    private func color(_ hex: String) throws -> RGBAColor {
        try #require(RGBAColor(hex: hex))
    }

    /// One short label per error, so a test can assert which problems were found and in what order without quoting
    /// the wording of each reason.
    private func labels(_ errors: [ThemeError]) -> [String] {
        errors.map { error in
            switch error {
            case .invalidValue(let path, _): "invalid \(path)"
            case .unknownToken(let key): "unknown \(key)"
            case .missingPaletteKey(let token, let key): "dangling \(token) -> \(key)"
            default: "\(error)"
            }
        }
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

    @Test(
        "a typo inside a token is reported with its path, not ignored",
        arguments: [
            (#"{"typography": {"body": {"sizee": 20}}}"#, "typography.body.sizee"),
            (#"{"typography": {"body": {"size": 14, "weigth": "bold"}}}"#, "typography.body.weigth"),
            (##"{"palette": {"blue": {"ligth": "#000000"}}}"##, "palette.blue.ligth"),
            (
                ##"{"palette": {"ocean": {"light": "#000000", "dark": "#111111", "mid": "#222222"}}}"##,
                "palette.ocean.mid"
            ),
            (#"{"overlay": {"widht": 400}}"#, "overlay.widht"),
        ])
    func typoInsideAToken(body: String, expectedPath: String) {
        let result = load(adding: body)
        #expect(result.theme == .default)
        #expect(result.errors == [.unknownToken(expectedPath)])
    }

    @Test("typos in different places are all reported, in name order")
    func typosAddUp() {
        let result = load(
            adding:
                ##"{"typography": {"body": {"sizee": 20}}, "palette": {"blue": {"ligth": "#000000"}}, "spacing": {"huge": 1}}"##
        )
        #expect(
            labels(result.errors) == [
                "unknown palette.blue.ligth", "unknown spacing.huge", "unknown typography.body.sizee",
            ])
    }

    @Test("a typo in a new palette entry does not hide a bad color in the same entry")
    func typoNextToABadColor() {
        let result = load(adding: ##"{"palette": {"ocean": {"ligth": "#000000", "dark": "#GG0000"}}}"##)
        #expect(
            labels(result.errors) == [
                "unknown palette.ocean.ligth", "invalid palette.ocean.dark", "invalid palette.ocean.light",
            ])
    }

    @Test("an unknown key whose value is also bad is reported once, as unknown")
    func unknownKeyWithABadValue() {
        let result = load(adding: #"{"spacing": {"huge": "x"}, "typography": {"body": {"sizee": "big"}}}"#)
        #expect(labels(result.errors) == ["unknown spacing.huge", "unknown typography.body.sizee"])
    }

    // MARK: Every problem, not the first

    @Test("two bad values are both reported")
    func twoBadValues() {
        let result = load(adding: #"{"spacing": {"md": "wide"}, "overlay": {"edge": "left"}}"#)
        #expect(result.theme == .default)
        #expect(labels(result.errors) == ["invalid overlay.edge", "invalid spacing.md"])
    }

    @Test("several bad values in one table are all reported, in path order")
    func badValuesInOneTable() {
        let result = load(adding: #"{"spacing": {"xl": "a", "md": true, "lg": [1]}}"#)
        #expect(labels(result.errors) == ["invalid spacing.lg", "invalid spacing.md", "invalid spacing.xl"])
    }

    @Test("a file with a great many bad values is cut off at the limit, so loading stays quick")
    func manyBadValues() {
        let entries = (1...80).map { "\"c\($0)\": 5" }.joined(separator: ", ")
        let result = load(adding: "{\"palette\": {\(entries)}}")
        #expect(result.theme == .default)
        #expect(result.errors.count == ThemeLoader.valueErrorLimit)
        #expect(ThemeLoader.valueErrorLimit == 50)
        #expect(labels(result.errors).allSatisfy { $0.hasPrefix("invalid palette.c") })
    }

    @Test("a few bad values are all reported, below the limit")
    func fewBadValues() {
        let entries = (1...12).map { "\"c\($0)\": 5" }.joined(separator: ", ")
        let result = load(adding: "{\"palette\": {\(entries)}}")
        #expect(result.errors.count == 12)
    }

    @Test("both colors of a new palette entry are reported when both are bad")
    func twoBadColorsInOneEntry() {
        let result = load(adding: ##"{"palette": {"ocean": {"light": "#GG0000", "dark": "#ZZ0000"}}}"##)
        #expect(labels(result.errors) == ["invalid palette.ocean.dark", "invalid palette.ocean.light"])
    }

    @Test("a bad value, a missing part, a bad table, and a bad hex are found in one pass")
    func mixedBadValues() {
        let result = load(
            adding: ##"""
                {"name": 7, "radii": [1, 2], "typography": {"body": {"weight": "heavy"}},
                 "palette": {"ocean": {"light": "#GG0000", "dark": "#000000"}, "lake": {"dark": "#000000"}}}
                """##)
        #expect(
            labels(result.errors) == [
                "invalid name", "invalid palette.lake.light", "invalid palette.ocean.light", "invalid radii",
                "invalid typography.body.weight",
            ])
    }

    @Test(
        "a color that points at a palette entry whose own value is bad is not also reported as dangling",
        arguments: [
            (##"{"ocean": {"light": "#GG0000", "dark": "#000000"}}"##, "invalid palette.ocean.light"),
            (##"{"ocean": "#0077B6"}"##, "invalid palette.ocean"),
        ])
    func badEntryIsNotDangling(palette: String, expectedLabel: String) {
        let result = load(adding: #"{"palette": \#(palette), "colors": {"accent.primary": "ocean"}}"#)
        #expect(labels(result.errors) == [expectedLabel])
    }

    @Test("every kind of problem is reported together, in a fixed order")
    func everyKindTogether() {
        let result = load(
            adding: ##"""
                {"spacing": {"huge": 40, "md": "wide"}, "radii": {"lg": -2},
                 "palette": {"ocean": {"light": "#GG0000", "dark": "#000000"}},
                 "colors": {"accent.primary": "nowhere", "accent.recording": "ocean"}}
                """##)
        #expect(result.theme == .default)
        #expect(
            labels(result.errors) == [
                "unknown spacing.huge", "invalid palette.ocean.light", "invalid spacing.md",
                "dangling accent.primary -> nowhere", "invalid radii.lg",
            ])
    }

    // MARK: Numbers

    @Test(
        "a negative number is rejected with its path, wherever a theme holds a number",
        arguments: [
            (#"{"spacing": {"md": -4}}"#, "spacing.md"),
            (#"{"radii": {"lg": -1}}"#, "radii.lg"),
            (#"{"motion": {"fast": -0.5}}"#, "motion.fast"),
            (#"{"typography": {"body": {"size": -13}}}"#, "typography.body.size"),
            (#"{"overlay": {"width": -380}}"#, "overlay.width"),
            (#"{"overlay": {"cornerRadius": -1}}"#, "overlay.cornerRadius"),
            (#"{"overlay": {"offset": -80}}"#, "overlay.offset"),
        ])
    func negativeNumber(body: String, expectedPath: String) {
        let result = load(adding: body)
        #expect(result.theme == .default)
        #expect(labels(result.errors) == ["invalid \(expectedPath)"])
        if case .invalidValue(_, let reason) = result.errors.first {
            #expect(reason.contains("0 or more"))
        }
    }

    @Test("zero is allowed: no spacing, no radius, and no animation are real choices")
    func zeroIsAllowed() {
        let result = load(adding: #"{"spacing": {"xs": 0}, "radii": {"sm": 0}, "motion": {"fast": 0}}"#)
        #expect(result.errors == [])
        #expect(result.theme.spacing["xs"] == 0)
    }

    @Test("a number that JSON text can only spell as infinity is rejected, and does not trap")
    func infinity() {
        // Foundation reads -1e999 as -infinity but cannot write it back, so merging used to crash on it.
        let result = load(adding: #"{"spacing": {"md": -1e999}}"#)
        #expect(result.theme == .default)
        #expect(labels(result.errors) == ["invalid spacing.md"])
    }

    @Test("an infinite number inside a list is reported too, and does not trap")
    func infinityInAList() {
        let result = load(adding: #"{"spacing": {"md": [1, -1e999, -1e999]}, "radii": [[-1e999]]}"#)
        #expect(result.theme == .default)
        #expect(labels(result.errors) == ["invalid radii", "invalid spacing.md"])
    }

    @Test("a number too large for a double is malformed JSON")
    func tooLarge() {
        let result = load(adding: #"{"spacing": {"md": 1e999}}"#)
        #expect(result.theme == .default)
        #expect(result.errors.count == 1)
        if case .malformedJSON = result.errors.first {
        } else {
            Issue.record("expected malformedJSON, got \(result.errors)")
        }
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
            (.unknownToken("spacing.huge"), "spacing.huge is not a key of the theme."),
            (.unreadable(file: "night.json", reason: "No such file."), "Cannot read night.json: No such file."),
            (.themeNotFound("night"), "There is no theme named night."),
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
