/// A theme with the light or dark value of every color picked. This is what views read, through `\.theme`, so they
/// never see a palette or an appearance.
public nonisolated struct ResolvedTheme: Sendable, Equatable {
    public let name: String
    public let appearance: Appearance
    public let overlay: OverlayGeometry
    private let colors: [ColorToken: RGBAColor]
    private let typography: [TypeToken: TypeStyle]
    private let spacings: [SpacingToken: Double]
    private let radii: [RadiusToken: Double]
    private let sizes: [SizeToken: Double]
    private let motions: [MotionToken: Double]

    /// The bundled theme in light appearance: what a view reads when nothing above it provides a theme.
    public static let standard: ResolvedTheme = {
        do {
            return try Theme.default.resolved(for: .light)
        } catch {
            preconditionFailure("The bundled theme does not resolve: \(error)")
        }
    }()

    /// `theme` must have no problems: `Theme.resolved(for:)` checks that.
    fileprivate init(_ theme: Theme, appearance: Appearance) {
        name = theme.name
        self.appearance = appearance
        overlay = theme.overlay
        colors = Self.table(theme.colors.compactMapValues { theme.palette[$0]?.value(for: appearance) })
        typography = Self.table(theme.typography)
        spacings = Self.table(theme.spacing)
        radii = Self.table(theme.radii)
        sizes = Self.table(theme.sizes)
        motions = Self.table(theme.motion)
    }

    public func color(_ token: ColorToken) -> RGBAColor { colors[token, orFail: token] }
    public func type(_ token: TypeToken) -> TypeStyle { typography[token, orFail: token] }
    public func spacing(_ token: SpacingToken) -> Double { spacings[token, orFail: token] }
    public func radius(_ token: RadiusToken) -> Double { radii[token, orFail: token] }
    public func size(_ token: SizeToken) -> Double { sizes[token, orFail: token] }
    public func motion(_ token: MotionToken) -> Double { motions[token, orFail: token] }

    private static func table<T: ThemeToken, V>(_ values: [String: V]) -> [T: V] {
        Dictionary(uniqueKeysWithValues: T.allCases.map { ($0, values[$0.rawValue, orFail: $0]) })
    }
}

nonisolated extension Dictionary {
    /// Every table of a resolved theme has all its tokens, because the theme was checked first.
    fileprivate subscript<T: ThemeToken>(key: Key, orFail token: T) -> Value {
        guard let value = self[key] else {
            preconditionFailure("A resolved theme lacks \(token.key). Theme.resolved(for:) should have rejected it.")
        }
        return value
    }
}

nonisolated extension Theme {
    /// Everything that keeps this theme from being used: tokens it lacks, then colors that point at a palette entry
    /// it lacks, then numbers that are negative or not finite.
    public func problems() -> [ThemeError] {
        let missing = ThemeTokenCatalog.missingKeys(in: self).map(ThemeError.missingToken)
        let dangling = colors.sorted { $0.key < $1.key }
            .filter { palette[$0.value] == nil }
            .map { ThemeError.missingPaletteKey(token: $0.key, paletteKey: $0.value) }
        let outOfRange = numbers.sorted { $0.key < $1.key }
            .filter { !ThemeError.isAllowed($0.value) }
            .map { ThemeError.notAllowed($0.value, at: $0.key) }
        return missing + dangling + outOfRange
    }

    /// The theme in light or dark appearance. It throws the first of `problems()`.
    public func resolved(for appearance: Appearance) throws(ThemeError) -> ResolvedTheme {
        if let problem = problems().first { throw problem }
        return ResolvedTheme(self, appearance: appearance)
    }

    /// Every number of the theme by its path: type sizes, spaces, radii, component sizes, durations, and the overlay
    /// geometry.
    private var numbers: [String: Double] {
        var numbers: [String: Double] = [:]
        for (name, value) in spacing { numbers["\(SpacingToken.group).\(name)"] = value }
        for (name, value) in radii { numbers["\(RadiusToken.group).\(name)"] = value }
        for (name, value) in sizes { numbers["\(SizeToken.group).\(name)"] = value }
        for (name, value) in motion { numbers["\(MotionToken.group).\(name)"] = value }
        for (name, style) in typography { numbers["\(TypeToken.group).\(name).size"] = style.size }
        for (field, value) in [
            ("width", overlay.width), ("cornerRadius", overlay.cornerRadius), ("offset", overlay.offset),
        ] {
            numbers["\(OverlayGeometry.group).\(field)"] = value
        }
        return numbers
    }
}

nonisolated extension ThemeError {
    /// Lengths, sizes, and durations are finite and not negative. Zero is allowed: no space and no animation are
    /// real choices.
    static func isAllowed(_ number: Double) -> Bool {
        number.isFinite && number >= 0
    }

    static func notAllowed(_ number: Double, at path: String) -> ThemeError {
        .invalidValue(path: path, reason: "\(number) is not allowed. Use a finite number of 0 or more.")
    }
}
