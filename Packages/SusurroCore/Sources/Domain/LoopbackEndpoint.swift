import Foundation

/// The rule for the address of a server that the user runs on this Mac. Audio goes there, so only an address that
/// cannot leave this Mac is accepted.
public enum LoopbackEndpoint {
    private static let hosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The URL for `text` when it is an http or https address whose host is this Mac, and nil otherwise. A host that
    /// only looks like one (`localhost.example.com`, `127.0.0.1.evil.test`), an address with credentials, and any other
    /// scheme are refused.
    public static func validated(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            components.user == nil, components.password == nil,
            let host = components.host?.lowercased(), hosts.contains(host),
            let url = components.url
        else { return nil }
        return url
    }
}

/// The rule for the path of a program the user configured to run.
public enum ExecutablePath {
    /// Why a path cannot be run.
    public enum Problem: Error, Sendable, Equatable {
        case empty
        case notAbsolute
        case missing
        case notExecutable
    }

    /// Checks the path with the answers of the file system, which the caller passes so that a test needs no real file.
    public static func validate(
        _ path: String, exists: (String) -> Bool, isExecutable: (String) -> Bool, isDirectory: (String) -> Bool
    ) -> Problem? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if !trimmed.hasPrefix("/") { return .notAbsolute }
        if !exists(trimmed) || isDirectory(trimmed) { return .missing }
        if !isExecutable(trimmed) { return .notExecutable }
        return nil
    }

    /// The same check against the real file system.
    public static func validate(_ path: String) -> Problem? {
        let manager = FileManager.default
        return validate(
            path,
            exists: { manager.fileExists(atPath: $0) },
            isExecutable: { manager.isExecutableFile(atPath: $0) },
            isDirectory: {
                var isDirectory: ObjCBool = false
                return manager.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
            })
    }
}
