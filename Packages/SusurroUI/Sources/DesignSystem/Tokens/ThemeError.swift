/// Why a theme cannot be used.
public nonisolated enum ThemeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The text is not JSON, or not a JSON object.
    case malformedJSON(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// A value has the wrong type or form, or a number is out of range. `path` locates it, such as
    /// `palette.ocean.light`.
    case invalidValue(path: String, reason: String)
    /// A file has a key the theme does not use, most likely a typo. `String` is its path, such as `spacing.huge` or
    /// `typography.body.sizee`.
    case unknownToken(String)
    case unreadable(file: String, reason: String)
    /// The theme in use is a file that is no longer there.
    case themeNotFound(String)
    /// A token of the catalog has no value. `String` is the token as `group.name`.
    case missingToken(String)
    /// A color points at a palette entry that does not exist.
    case missingPaletteKey(token: String, paletteKey: String)

    public var description: String {
        switch self {
        case .malformedJSON(let reason):
            "The file is not valid JSON: \(reason)"
        case .unsupportedSchemaVersion(let found, let supported):
            "The file uses schema version \(found), and this build reads version \(supported)."
        case .invalidValue(let path, let reason):
            "\(path) is not valid: \(reason)"
        case .unknownToken(let key):
            "\(key) is not a key of the theme."
        case .unreadable(let file, let reason):
            "Cannot read \(file): \(reason)"
        case .themeNotFound(let id):
            "There is no theme named \(id)."
        case .missingToken(let key):
            "The theme does not define \(key)."
        case .missingPaletteKey(let token, let paletteKey):
            "\(ColorToken.group).\(token) points at the palette entry \"\(paletteKey)\", which does not exist."
        }
    }
}
