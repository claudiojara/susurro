import Foundation

/// A color in sRGB with each component from 0 to 1. A theme file writes it as `#RRGGBB`, or as `#RRGGBBAA` when it is
/// not opaque.
public nonisolated struct RGBAColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Reads `#RRGGBB` or `#RRGGBBAA`, in either case. Anything else is nil.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        // `UInt64(_:radix:)` alone would accept a leading sign.
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
            let value = UInt64(digits, radix: 16)
        else { return nil }
        let rgba = digits.count == 8 ? value : value << 8 | 0xFF
        func channel(_ shift: UInt64) -> Double { Double(rgba >> shift & 0xFF) / 255 }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    /// The shortest uppercase form that keeps every component: `#RRGGBB` while the color is opaque.
    public var hex: String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        let opaque = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha == 1 ? opaque : opaque + String(format: "%02X", byte(alpha))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = RGBAColor(hex: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" is not a color. Write #RRGGBB or #RRGGBBAA.")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
