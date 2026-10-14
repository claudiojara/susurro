import DesignSystem
import Foundation

/// Where a word of the views comes from: the string catalog of this module (`Localizable.xcstrings`), by key, in the
/// language the user chose (`InterfaceLocale`). The text written here is the English one, and it is what the word is
/// when the catalog has no entry for the key. A view that reads one is drawn again when the language changes.
nonisolated enum L10n {
    static func string(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
        InterfaceLocale.string(key, defaultValue, bundle: .module)
    }
}
