import Foundation

/// Every visual value of the app, as data. A theme file is this struct written as JSON (see `docs/theming.md`), and the
/// bundled `DefaultTheme.json` defines every token, so a theme file only lists what it changes.
///
/// Views never read a `Theme`. They read a `ResolvedTheme` from the environment, which has picked the light or dark
/// value of every color.
public nonisolated struct Theme: Codable, Sendable, Equatable {
    /// The `schemaVersion` this build reads.
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String
    /// Raw colors by name, each with a light and a dark value. Only `colors` refers to them.
    public var palette: [String: PaletteColor]
    /// For each `ColorToken`, the name of its palette entry.
    public var colors: [String: String]
    public var typography: [String: TypeStyle]
    public var spacing: [String: Double]
    public var radii: [String: Double]
    public var sizes: [String: Double]
    public var motion: [String: Double]
    public var overlay: OverlayGeometry

    /// The theme that ships with the app. Every other theme inherits what it leaves out from this one.
    public static let `default`: Theme = {
        do {
            return try JSONDecoder().decode(Theme.self, from: bundledData)
        } catch {
            preconditionFailure("DefaultTheme.json is not a valid theme: \(error)")
        }
    }()

    /// The bundled theme as a JSON object, the base that a theme file is merged onto.
    static var bundledObject: [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: bundledData) as? [String: Any] else {
            preconditionFailure("DefaultTheme.json is not a JSON object")
        }
        return object
    }

    private static let bundledData: Data = {
        do {
            guard let url = Bundle.module.url(forResource: "DefaultTheme", withExtension: "json") else {
                preconditionFailure("DefaultTheme.json is not in the DesignSystem bundle")
            }
            return try Data(contentsOf: url)
        } catch {
            preconditionFailure("DefaultTheme.json cannot be read: \(error)")
        }
    }()
}

public nonisolated struct PaletteColor: Codable, Sendable, Equatable {
    public var light: RGBAColor
    public var dark: RGBAColor

    /// Spelled out so the loader can tell a typo in a field name from a field.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case light, dark
    }

    func value(for appearance: Appearance) -> RGBAColor {
        appearance == .light ? light : dark
    }
}

public nonisolated struct TypeStyle: Codable, Sendable, Equatable {
    /// Points.
    public var size: Double
    public var weight: TypeWeight
    public var design: TypeDesign

    enum CodingKeys: String, CodingKey, CaseIterable {
        case size, weight, design
    }
}

public nonisolated enum TypeWeight: String, Codable, Sendable {
    case regular, medium, semibold, bold
}

public nonisolated enum TypeDesign: String, Codable, Sendable {
    case standard, rounded, monospaced, serif
}

/// Where the recording overlay sits and how big it is. Lengths are in points.
public nonisolated struct OverlayGeometry: Codable, Sendable, Equatable {
    public static let group = "overlay"

    public var width: Double
    public var cornerRadius: Double
    /// The distance from the screen edge.
    public var offset: Double
    public var edge: ScreenEdge

    enum CodingKeys: String, CodingKey, CaseIterable {
        case width, cornerRadius, offset, edge
    }
}

public nonisolated enum ScreenEdge: String, Codable, Sendable {
    case top, bottom
}
