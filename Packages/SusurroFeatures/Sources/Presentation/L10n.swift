import Foundation

/// Where a user-facing sentence comes from: the string catalog of this module (`Localizable.xcstrings`), by key. The text
/// written here is the English one, and it is what the sentence is when the catalog has no entry for the key, so a missing
/// entry shows English and never the key.
enum L10n {
    static func string(_ key: StaticString, _ defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: .module)
    }
}
