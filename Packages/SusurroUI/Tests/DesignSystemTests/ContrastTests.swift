import Testing

@testable import DesignSystem

@Suite("Contrast")
struct ContrastTests {
    /// WCAG 2 level AA for text of any size below 18 pt, which all the type roles are.
    private static let required = 4.5

    @Test("the ratio is the WCAG one: 21 for black on white, 1 for a color on itself, the same either way round")
    func ratioIsWCAG() throws {
        let black = RGBAColor(red: 0, green: 0, blue: 0)
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        #expect(abs(black.contrastRatio(against: white) - 21) < 1e-9)
        #expect(abs(white.contrastRatio(against: black) - 21) < 1e-9)
        #expect(white.contrastRatio(against: white) == 1)
        // #767676 is the lightest gray that reaches 4.5 on white, and the guides give 4.54 for it.
        let gray = try #require(RGBAColor(hex: "#767676"))
        #expect(abs(gray.contrastRatio(against: white) - 4.54) < 0.005)
        let blue = try #require(RGBAColor(hex: "#0A64D8"))
        #expect(abs(blue.contrastRatio(against: white) - 5.49) < 0.005)
    }

    @Test("text that is not opaque is seen as it is painted over the background")
    func translucentTextIsComposited() {
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        let half = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let gray = RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        #expect(half.contrastRatio(against: white) == gray.contrastRatio(against: white))
        #expect(half.contrastRatio(against: white) < RGBAColor(red: 0, green: 0, blue: 0).contrastRatio(against: white))
    }

    /// The pairs of text and the color it is drawn on that the app has: the text roles on the surfaces, the tints (as the
    /// text of a pill or a label) on the surfaces, and the text on an accent fill. `surface.overlay` is translucent, so it
    /// is taken over the window.
    private static let pairs: [(text: ColorToken, background: ColorToken)] = {
        var pairs: [(ColorToken, ColorToken)] = []
        let surfaces: [ColorToken] = [.surfaceWindow, .surfaceRaised, .surfaceOverlay]
        let texts: [ColorToken] = [
            .textPrimary, .textSecondary, .accentPrimary, .accentRecording, .statusSuccess, .statusWarning,
            .statusError, .statusPending,
        ]
        for text in texts { for surface in surfaces { pairs.append((text, surface)) } }
        for fill: ColorToken in [.accentPrimary, .accentRecording, .statusError] { pairs.append((.textOnAccent, fill)) }
        return pairs
    }()

    nonisolated private static let appearances: [Appearance] = [.light, .dark]

    @Test("every pair of text and background meets AA in light and in dark", arguments: appearances)
    func everyPairMeetsAA(appearance: Appearance) throws {
        let theme = try Theme.default.resolved(for: appearance)
        let window = theme.color(.surfaceWindow)
        var failures: [String] = []
        for pair in Self.pairs {
            let background = theme.color(pair.background).composited(over: window)
            let ratio = theme.color(pair.text).contrastRatio(against: background)
            if ratio < Self.required {
                failures.append(
                    "\(pair.text.rawValue) on \(pair.background.rawValue): \(String(format: "%.2f", ratio))")
            }
        }
        #expect(failures == [], "In \(appearance), below \(Self.required):1")
    }

    @Test("the pairs cover every text role, every tint, and every fill that carries text")
    func pairsAreComplete() {
        let texts = Set(Self.pairs.map(\.text))
        let backgrounds = Set(Self.pairs.map(\.background))
        for role: ColorToken in [.textPrimary, .textSecondary, .textOnAccent] { #expect(texts.contains(role)) }
        for tint in Tint.allCases { #expect(texts.contains(tint.color), "\(tint) is never checked as text") }
        for surface: ColorToken in [.surfaceWindow, .surfaceRaised, .surfaceOverlay] {
            #expect(backgrounds.contains(surface))
        }
        for fill: ColorToken in [.accentPrimary, .accentRecording, .statusError] {
            #expect(
                Self.pairs.contains { $0.text == .textOnAccent && $0.background == fill }, "\(fill) is never a fill")
        }
    }
}
