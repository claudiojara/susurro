import Domain

/// Setting keys that are stored under one name, which would make them read and overwrite each other.
public struct DuplicateSettingKeys: Error, Equatable, CustomStringConvertible {
    /// Each name that more than one key has, in the order its repetition was first found.
    public let names: [String]

    public init(names: [String]) {
        self.names = names
    }

    public var description: String {
        "Setting keys share a storage name: \(names.joined(separator: ", "))"
    }
}

/// Fails the test that calls it when two of `keys` have the same storage name, whatever their value types. A catalog of
/// keys passes its whole list: `try requireUniqueStorageNames(AppSettings.all)`.
public func requireUniqueStorageNames(_ keys: [any AnySettingKey]) throws {
    var seen: Set<String> = []
    var duplicates: [String] = []
    for key in keys where !seen.insert(key.storageName).inserted && !duplicates.contains(key.storageName) {
        duplicates.append(key.storageName)
    }
    if !duplicates.isEmpty { throw DuplicateSettingKeys(names: duplicates) }
}
