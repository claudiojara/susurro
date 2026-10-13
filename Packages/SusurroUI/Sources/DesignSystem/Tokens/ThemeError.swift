/// Why a theme cannot be used.
public nonisolated enum ThemeError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A token of the catalog has no value. `String` is the token as `group.name`.
    case missingToken(String)
    /// A color points at a palette entry that does not exist.
    case missingPaletteKey(token: String, paletteKey: String)

    public var description: String {
        switch self {
        case .missingToken(let key):
            "The theme does not define \(key)."
        case .missingPaletteKey(let token, let paletteKey):
            "\(ColorToken.group).\(token) points at the palette entry \"\(paletteKey)\", which does not exist."
        }
    }
}
