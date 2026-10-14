import Foundation

/// A basic value as a store holds it, told apart by kind.
///
/// The preferences database hands every number back as an `NSNumber`, and an `NSNumber` converts to a Bool, an Int or a
/// Double whenever it is asked to: `as? Bool` reads a stored 1 as true, `as? Int` reads a stored true as 1, and
/// `as? Double` reads a stored 5 as 5.0. A setting would then hold a value nobody set, and the in-memory store, which
/// keeps native Swift values, would read the same data as the default. A key reads a number only as the kind it was
/// stored as, whatever the store, so both stores answer alike.
enum StoredScalar {
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case text(String)

    init?(_ stored: Any) {
        if let text = stored as? String {
            self = .text(text)
        } else if let number = stored as? NSNumber {
            // A Bool is its own kind of Core Foundation object, and a real is told from an integer by its storage type.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .real(number.doubleValue)
            } else if let integer = number as? Int {
                self = .integer(integer)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    /// The native Swift value, which converts only to its own type.
    var value: any Sendable {
        switch self {
        case .bool(let value): value
        case .integer(let value): value
        case .real(let value): value
        case .text(let value): value
        }
    }

    /// `stored` as a `Value`, or nil when it is not that kind of value.
    static func read<Value: SettingStorable>(_ stored: Any, as type: Value.Type) -> Value? {
        StoredScalar(stored)?.value as? Value
    }
}
