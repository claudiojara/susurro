import SwiftUI

/// Puts a theme in the environment of the views below, resolved for the appearance to show. The appearance is the
/// system's, as the color scheme tells it, unless `override` names one. Below the provider the color scheme is that
/// appearance too, so system controls follow it, and a change of the system's re-resolves every color.
public struct ThemeProvider: ViewModifier {
    private let theme: Theme
    private let override: AppearanceOverride
    @Environment(\.colorScheme) private var systemScheme

    public init(theme: Theme, override: AppearanceOverride = .system) {
        self.theme = theme
        self.override = override
    }

    public func body(content: Content) -> some View {
        let appearance = override.appearance(whenSystemIs: systemScheme == .dark ? .dark : .light)
        content
            .environment(\.theme, resolved(for: appearance))
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
    }

    /// A theme that does not resolve, which the loader never returns, shows the bundled one.
    private func resolved(for appearance: Appearance) -> ResolvedTheme {
        (try? theme.resolved(for: appearance)) ?? (try? Theme.default.resolved(for: appearance)) ?? .standard
    }
}

extension View {
    public func themed(_ theme: Theme, override: AppearanceOverride = .system) -> some View {
        modifier(ThemeProvider(theme: theme, override: override))
    }
}
