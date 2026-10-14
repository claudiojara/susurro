/// The tokens a complete theme defines, taken from the token enums so there is one list to keep.
public nonisolated enum ThemeTokenCatalog {
    /// One group of a theme file: the names it must define, how to read the names a theme defines in it, and, when a
    /// token is an object, the fields that object may have.
    struct Group: Sendable {
        let name: String
        let expected: Set<String>
        /// The keys inside a token that is an object, such as `size` for a type style. Empty when a token is one value.
        let fields: Set<String>
        let defined: @Sendable (Theme) -> Set<String>

        init<T: ThemeToken>(
            _ tokens: T.Type, fields: Set<String> = [], defined: @escaping @Sendable (Theme) -> Set<String>
        ) {
            name = T.group
            expected = Set(T.allCases.map(\.rawValue))
            self.fields = fields
            self.defined = defined
        }

        /// The overlay geometry is a struct, so a theme cannot lack one of its fields.
        private init(overlay names: Set<String>) {
            name = OverlayGeometry.group
            expected = names
            fields = []
            defined = { _ in names }
        }

        static let overlay = Group(overlay: ThemeTokenCatalog.names(of: OverlayGeometry.CodingKeys.self))

        func qualified(_ names: Set<String>) -> [String] {
            names.map { "\(name).\($0)" }
        }
    }

    static let groups: [Group] = [
        Group(ColorToken.self) { Set($0.colors.keys) },
        Group(TypeToken.self, fields: names(of: TypeStyle.CodingKeys.self)) { Set($0.typography.keys) },
        Group(SpacingToken.self) { Set($0.spacing.keys) },
        Group(RadiusToken.self) { Set($0.radii.keys) },
        Group(SizeToken.self) { Set($0.sizes.keys) },
        Group(LayoutToken.self) { Set($0.layout.keys) },
        Group(MotionToken.self) { Set($0.motion.keys) },
        .overlay,
    ]

    /// The fields of a palette color. The palette is not a group: its names are the theme's own, not tokens.
    static let paletteFields = names(of: PaletteColor.CodingKeys.self)

    /// Every token as `group.name`, such as `spacing.md` or `colors.text.primary`.
    public static let allKeys = Set(groups.flatMap { $0.qualified($0.expected) })

    /// The keys of `allKeys` that `theme` does not define, in order.
    public static func missingKeys(in theme: Theme) -> [String] {
        allKeys.subtracting(definedKeys(in: theme)).sorted()
    }

    static func definedKeys(in theme: Theme) -> Set<String> {
        Set(groups.flatMap { $0.qualified($0.defined(theme)) })
    }

    private static func names<Keys: CaseIterable & RawRepresentable<String>>(of keys: Keys.Type) -> Set<String> {
        Set(Keys.allCases.map(\.rawValue))
    }
}
