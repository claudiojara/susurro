import DesignSystem
import Domain
import Foundation

extension InterfaceLanguage {
    /// Shows the app's words in this language from now on, resolving `system` against the languages the user prefers.
    /// Every window, the menu, and the overlay follow at once, since they read `InterfaceLocale`.
    public func apply(preferredLanguages: [String] = Locale.preferredLanguages, to holder: InterfaceLocale = .shared) {
        holder.set(resolved(preferredLanguages: preferredLanguages))
    }
}
