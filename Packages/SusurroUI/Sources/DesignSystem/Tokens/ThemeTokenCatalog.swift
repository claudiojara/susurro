/// The tokens a complete theme defines, taken from the token enums so there is one list to keep.
public nonisolated enum ThemeTokenCatalog {
    /// The names each group must define, by group.
    static let names: [String: Set<String>] = [
        ColorToken.group: names(of: ColorToken.self),
        TypeToken.group: names(of: TypeToken.self),
        SpacingToken.group: names(of: SpacingToken.self),
        RadiusToken.group: names(of: RadiusToken.self),
        MotionToken.group: names(of: MotionToken.self),
        OverlayGeometry.group: Set(OverlayGeometry.CodingKeys.allCases.map(\.rawValue)),
    ]

    /// Every token as `group.name`, such as `spacing.md` or `colors.text.primary`.
    public static let allKeys: Set<String> = qualified(names)

    /// The keys of `allKeys` that `theme` does not define, in order.
    public static func missingKeys(in theme: Theme) -> [String] {
        allKeys.subtracting(definedKeys(in: theme)).sorted()
    }

    static func definedKeys(in theme: Theme) -> Set<String> {
        qualified(theme.definedNames)
    }

    private static func names<T: ThemeToken>(of _: T.Type) -> Set<String> {
        Set(T.allCases.map(\.rawValue))
    }

    private static func qualified(_ namesByGroup: [String: Set<String>]) -> Set<String> {
        Set(namesByGroup.flatMap { group, names in names.map { "\(group).\($0)" } })
    }
}
