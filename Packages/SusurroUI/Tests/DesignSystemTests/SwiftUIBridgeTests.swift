import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
@Suite("SwiftUI bridge")
struct SwiftUIBridgeTests {
    nonisolated private static let hexes = ["#0A64D8", "#FFFFFF", "#000000", "#00000080", "#D92D20F2"]

    @Test("a color becomes the SwiftUI color with the same sRGB components", arguments: hexes)
    func colorKeepsItsComponents(hex: String) throws {
        let color = try #require(RGBAColor(hex: hex))
        let resolved = color.swiftUIColor.resolve(in: EnvironmentValues())
        #expect(abs(Double(resolved.red) - color.red) < 0.0001)
        #expect(abs(Double(resolved.green) - color.green) < 0.0001)
        #expect(abs(Double(resolved.blue) - color.blue) < 0.0001)
        #expect(abs(Double(resolved.opacity) - color.alpha) < 0.0001)
    }

    nonisolated private static let weights: [(TypeWeight, Font.Weight)] = [
        (.regular, .regular), (.medium, .medium), (.semibold, .semibold), (.bold, .bold),
    ]
    nonisolated private static let designs: [(TypeDesign, Font.Design)] = [
        (.standard, .default), (.rounded, .rounded), (.monospaced, .monospaced), (.serif, .serif),
    ]

    @Test("a type style becomes the system font of its size, weight, and design")
    func fontKeepsItsStyle() {
        for (weight, expectedWeight) in Self.weights {
            for (design, expectedDesign) in Self.designs {
                let style = TypeStyle(size: 13, weight: weight, design: design)
                #expect(style.swiftUIFont == .system(size: 13, weight: expectedWeight, design: expectedDesign))
            }
        }
        #expect(Self.weights.count * Self.designs.count == 16)
        let small = TypeStyle(size: 11, weight: .regular, design: .standard)
        let large = TypeStyle(size: 20, weight: .regular, design: .standard)
        #expect(small.swiftUIFont != large.swiftUIFont)
    }

    @Test("a resolved theme hands out the color of a token for its own appearance")
    func themeColors() throws {
        let light = try Theme.default.resolved(for: .light)
        let dark = try Theme.default.resolved(for: .dark)
        for token in ColorToken.allCases {
            #expect(light.swiftUIColor(token) == light.color(token).swiftUIColor)
            #expect(dark.swiftUIColor(token) == dark.color(token).swiftUIColor)
        }
        #expect(light.swiftUIColor(.surfaceWindow) != dark.swiftUIColor(.surfaceWindow))
    }

    @Test("a resolved theme hands out the font of a type token")
    func themeFonts() throws {
        let theme = try Theme.default.resolved(for: .light)
        for token in TypeToken.allCases {
            #expect(theme.font(token) == theme.type(token).swiftUIFont)
        }
        #expect(theme.font(.title) != theme.font(.caption))
    }

    @Test("a duration token is an ease of that duration, and no animation when motion is off")
    func easing() throws {
        let theme = try Theme.default.resolved(for: .light)
        #expect(theme.easing(.fast, motionEnabled: true) == .easeInOut(duration: theme.motion(.fast)))
        #expect(theme.easing(.slow, motionEnabled: true) == .easeInOut(duration: theme.motion(.slow)))
        #expect(theme.easing(.fast, motionEnabled: true) != theme.easing(.slow, motionEnabled: true))
        #expect(theme.easing(.fast, motionEnabled: false) == nil)
    }

    @Test("motion is on unless a view above turns it off")
    func motionEnabledEnvironment() {
        var environment = EnvironmentValues()
        #expect(environment.motionEnabled)
        environment.motionEnabled = false
        #expect(!environment.motionEnabled)
    }
}
