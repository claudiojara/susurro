import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
@Suite("Theme provider")
struct ThemeProviderTests {
    private final class Seen {
        var theme: ResolvedTheme?
        var scheme: ColorScheme?
    }

    /// Records what a view below the provider reads from the environment.
    private struct Probe: View {
        @Environment(\.theme) private var theme
        @Environment(\.colorScheme) private var scheme
        let seen: Seen

        var body: some View {
            seen.theme = theme
            seen.scheme = scheme
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    private func render<V: View>(_ view: V) {
        _ = ImageRenderer(content: view).cgImage
    }

    private func seen(_ theme: Theme = .default, override: AppearanceOverride, system: ColorScheme) -> Seen {
        let seen = Seen()
        render(Probe(seen: seen).themed(theme, override: override).environment(\.colorScheme, system))
        return seen
    }

    nonisolated private static let cases: [(system: ColorScheme, override: AppearanceOverride, shown: Appearance)] = [
        (.light, .system, .light), (.dark, .system, .dark),
        (.light, .dark, .dark), (.dark, .light, .light),
        (.light, .light, .light), (.dark, .dark, .dark),
    ]

    @Test("the appearance follows the system unless the override names one", arguments: cases)
    func appearanceFollowsOverride(system: ColorScheme, override: AppearanceOverride, shown: Appearance) throws {
        let seen = seen(override: override, system: system)
        let theme = try #require(seen.theme)
        #expect(theme.appearance == shown)
        #expect(theme == (try Theme.default.resolved(for: shown)))
        #expect(seen.scheme == (shown == .dark ? .dark : .light))
    }

    @Test("a view below the provider reads the theme it was given")
    func readsTheGivenTheme() throws {
        var custom = Theme.default
        custom.palette["testBlue"] = PaletteColor(
            light: RGBAColor(red: 0, green: 0, blue: 1), dark: RGBAColor(red: 0, green: 0.5, blue: 1))
        custom.colors["accent.primary"] = "testBlue"
        let light = try #require(seen(custom, override: .light, system: .dark).theme)
        let dark = try #require(seen(custom, override: .dark, system: .light).theme)
        #expect(light.color(.accentPrimary) == RGBAColor(red: 0, green: 0, blue: 1))
        #expect(dark.color(.accentPrimary) == RGBAColor(red: 0, green: 0.5, blue: 1))
        #expect(light.color(.accentPrimary) != (try Theme.default.resolved(for: .light)).color(.accentPrimary))
    }

    @Test("a theme that does not resolve shows the bundled one")
    func unresolvableThemeFallsBack() throws {
        var broken = Theme.default
        broken.colors["accent.primary"] = "nowhere"
        let theme = try #require(seen(broken, override: .dark, system: .light).theme)
        #expect(theme == (try Theme.default.resolved(for: .dark)))
    }

    @Test("without a provider a view reads the bundled theme in light appearance")
    func defaultsToTheBundledTheme() throws {
        let seen = Seen()
        render(Probe(seen: seen))
        #expect(seen.theme == (try Theme.default.resolved(for: .light)))
        #expect(seen.theme == ResolvedTheme.standard)
    }
}
