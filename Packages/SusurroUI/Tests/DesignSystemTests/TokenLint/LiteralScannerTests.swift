import Foundation
import Testing

@Suite("Literal scanner")
struct LiteralScannerTests {
    private func rules(in source: String) -> [LiteralRule] {
        LiteralScanner.violations(in: source, file: "View.swift").map(\.rule)
    }

    /// Every rule with the shortest source that breaks it. Each has a twin in `allowed` that differs only in being
    /// token-driven or zero, so a rule that matched too much would fail there.
    private static let violating: [(source: String, rule: LiteralRule)] = [
        ("Color(red: 1, green: 0, blue: 0)", .colorInitializer),
        ("Color.init(white: 0.5)", .colorInitializer),
        ("NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)", .colorInitializer),
        ("let c = Color.red", .namedColor),
        ("let c = NSColor.systemBlue", .namedColor),
        ("let c = 0xFF8800", .hexLiteral),
        (##"let c = "#FF8800""##, .hexLiteral),
        (##"let c = "#ff880080""##, .hexLiteral),
        (".font(.system(size: 13))", .fontSize),
        (".font(.system(size: size, weight: .bold, design: .rounded))", .fontSize),
        (#".font(.custom("Menlo", size: 12))"#, .fontSize),
        (".padding(8)", .spacing),
        (".padding(.horizontal, 12)", .spacing),
        (".padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))", .spacing),
        (".frame(width: 24, height: 24)", .spacing),
        (".frame(maxWidth: .infinity, minHeight: 44)", .spacing),
        (".frame(width: size * 2)", .spacing),
        (".offset(x: -4)", .spacing),
        ("VStack(spacing: 6) { Text(a) }", .spacing),
        ("VStack(spacing: -4) { Text(a) }", .spacing),
        ("Grid(horizontalSpacing: 8, verticalSpacing: 8) { }", .spacing),
        (".cornerRadius(8)", .cornerRadius),
        ("RoundedRectangle(cornerRadius: 10)", .cornerRadius),
        (".shadow(color: shadow, radius: 4)", .cornerRadius),
        (".easeInOut(duration: 0.3)", .animationDuration),
        (".linear(duration: 1)", .animationDuration),
        (".spring(response: 0.4, dampingFraction: 0.7)", .animationDuration),
        (".delay(0.2)", .animationDuration),
    ]

    private static let allowed: [String] = [
        "Color.clear",
        "RGBAColor(red: 1, green: 0, blue: 0)",
        "let token = ColorToken.textPrimary",
        "let mask = 0xFF",
        ##"let id = "#12""##,
        ##"let id = "#GG0000""##,
        ".font(theme.font(.body))",
        ".font(.body)",
        ".padding(0)",
        ".padding(.horizontal, 0)",
        ".padding(.md)",
        ".padding(.horizontal, theme.spacing(.md))",
        ".frame(width: 0.0)",
        ".frame(maxWidth: .infinity, alignment: .leading)",
        ".frame(width: size, height: size)",
        ".offset(x: shift)",
        "VStack(spacing: 0) { Text(a) }",
        "VStack(spacing: theme.spacing(.sm)) { Text(a) }",
        ".cornerRadius(0)",
        ".cornerRadius(radius)",
        "RoundedRectangle(cornerRadius: theme.radius(.md))",
        ".shadow(color: shadow, radius: radius)",
        ".easeInOut(duration: duration)",
        ".linear(duration: 0)",
        ".spring(response: response, dampingFraction: damping)",
        ".delay(delay)",
        "let x2 = 8 + count3",
        // The arguments of a call end at its closing parenthesis.
        "Text(a).padding(0).opacity(0.5)",
        ".frame(width: size).font(theme.font(.body)).lineLimit(2)",
    ]

    /// Text a scanner must not read as code: comments, and what is inside a string.
    private static let notCode: [String] = [
        "// Color(red: 1, green: 0, blue: 0)",
        "/// Never write `Color(` in a view.",
        "/* .cornerRadius(8) */",
        "let name = \"Color(red:) is not allowed\"",
        #"let note = "padding(8) and .cornerRadius(8)""#,
        ".padding(.horizontal, 0) // 12 would be too wide",
        ###"let raw = #"Color("quoted")"#"###,
        // The quotes inside a raw string do not end it.
        ###"let raw = #"a "b .padding(8) c" d"#"###,
        // A comment that holds a color is not a color.
        ##"// the accent is "#FF8800""##,
    ]

    @Test("each rule reports the source that breaks it, once", arguments: violating)
    func reportsEachRule(source: String, rule: LiteralRule) {
        #expect(rules(in: source) == [rule])
    }

    @Test("a token, a variable, or zero is not a violation", arguments: allowed)
    func allowsTokensAndZero(source: String) {
        #expect(rules(in: source) == [])
    }

    @Test("comments and the inside of strings are not code", arguments: notCode)
    func ignoresCommentsAndStrings(source: String) {
        #expect(rules(in: source) == [])
    }

    @Test("a violation after a comment or a string on the same line is still reported")
    func reportsCodeNextToComments() {
        #expect(rules(in: "/* a */ Color(white: 1) // b") == [.colorInitializer])
        #expect(rules(in: #"Text("a").padding(8)"#) == [.spacing])
        #expect(rules(in: "/* a /* b */ Color(white: 1) */ .cornerRadius(4)") == [.cornerRadius])
    }

    @Test("a call over several lines is reported at the line of its literal")
    func reportsTheLineOfTheLiteral() {
        let source = """
            Text("a")
                .frame(
                    width: 0,
                    height: 24
                )
                .background(
                    Color(
                        white: 1))
            """
        let found = LiteralScanner.violations(in: source, file: "View.swift")
        #expect(found.map(\.rule) == [.spacing, .colorInitializer])
        #expect(found.map(\.line) == [4, 7])
    }

    @Test("block comments and multi-line strings span lines")
    func skipsSpanningText() {
        let source = """
            /*
             Color(white: 1)
             */
            let text = \"\"\"
                .padding(8)
                \"\"\"
            .padding(8)
            """
        let found = LiteralScanner.violations(in: source, file: "View.swift")
        #expect(found.map(\.line) == [7])
    }

    @Test("a violation names its file, line, rule, and the text of the line")
    func describesAViolation() {
        let found = LiteralScanner.violations(in: "let a = 1\n    .padding(8)\n", file: "Atoms/Pill.swift")
        #expect(found.map(\.description) == ["Atoms/Pill.swift:2: spacing: .padding(8)"])
    }

    @Test("a folder scan reads every Swift file below it except the allowlisted folders")
    func scansFolders() throws {
        let folder = try ScratchFolder()
        try folder.write("Atoms/Pill.swift", "Text(a)\n    .padding(8)\n")
        try folder.write("Atoms/Deeper/Dot.swift", "let c = Color.red\n")
        try folder.write("Atoms/notes.txt", "Color(white: 1)\n")
        try folder.write("Tokens/Bridge.swift", "let c = Color(white: 1)\n")
        try folder.write("Clean.swift", "let a = 1\n")

        let everything = try LiteralScanner.scan(folder.url, allowing: [])
        #expect(
            everything.files == ["Atoms/Deeper/Dot.swift", "Atoms/Pill.swift", "Clean.swift", "Tokens/Bridge.swift"])
        #expect(
            everything.violations.map(\.description) == [
                "Atoms/Deeper/Dot.swift:1: namedColor: let c = Color.red",
                "Atoms/Pill.swift:2: spacing: .padding(8)",
                "Tokens/Bridge.swift:1: colorInitializer: let c = Color(white: 1)",
            ])

        let allowing = try LiteralScanner.scan(folder.url, allowing: [folder.file("Tokens")])
        #expect(allowing.files == ["Atoms/Deeper/Dot.swift", "Atoms/Pill.swift", "Clean.swift"])
        #expect(allowing.violations.map(\.rule) == [.namedColor, .spacing])
    }
}
