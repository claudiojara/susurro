import Foundation

/// What loading a theme file gave. `errors` is empty when the file was used. Otherwise `theme` is the bundled default
/// and `errors` says everything that was wrong with the file, so it can be shown or logged.
public nonisolated struct ThemeLoadResult: Sendable, Equatable {
    public let theme: Theme
    public let errors: [ThemeError]
}

/// Reads a theme file and merges it onto the bundled default, key by key, so a file lists only what it changes. A file
/// that cannot be used as a whole is rejected as a whole: loading never returns a theme that is half applied.
///
/// Loading is `nonisolated`, so a caller can read and decode files away from the main actor.
public nonisolated enum ThemeLoader {
    public static func load(contentsOf url: URL) -> ThemeLoadResult {
        do {
            return load(data: try Data(contentsOf: url))
        } catch {
            return rejected([.unreadable(file: url.lastPathComponent, reason: error.localizedDescription)])
        }
    }

    public static func load(data: Data) -> ThemeLoadResult {
        let file: [String: Any]
        do throws(ThemeError) {
            file = try parseObject(data)
            try checkVersion(of: file)
        } catch {
            return rejected([error])
        }
        var errors = unknownTokens(in: file)
        do throws(ThemeError) {
            let theme = try decode(file, over: Theme.bundledObject)
            errors += theme.problems()
            if errors.isEmpty { return ThemeLoadResult(theme: theme, errors: []) }
        } catch {
            errors.append(error)
        }
        return rejected(errors)
    }

    private static func rejected(_ errors: [ThemeError]) -> ThemeLoadResult {
        ThemeLoadResult(theme: .default, errors: errors)
    }

    // MARK: Reading

    private static func parseObject(_ data: Data) throws(ThemeError) -> [String: Any] {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw .malformedJSON(detail ?? error.localizedDescription)
        }
        guard let object = value as? [String: Any] else { throw .malformedJSON("The top level must be an object.") }
        return object
    }

    /// Checked before anything else: a file of another version may have a shape this build cannot describe.
    private static func checkVersion(of file: [String: Any]) throws(ThemeError) {
        guard let version = file["schemaVersion"] as? Int else {
            let reason = file["schemaVersion"] == nil ? "is missing." : "must be a whole number."
            throw .invalidValue(path: "schemaVersion", reason: reason)
        }
        guard version == Theme.supportedSchemaVersion else {
            throw .unsupportedSchemaVersion(found: version, supported: Theme.supportedSchemaVersion)
        }
    }

    // MARK: Checking

    private static let fileKeys = Set(["schemaVersion", "name", "palette"]).union(ThemeTokenCatalog.names.keys)

    /// Tokens the file names that the catalog does not list. Decoding would skip them without a word.
    private static func unknownTokens(in file: [String: Any]) -> [ThemeError] {
        var unknown = file.keys.filter { !fileKeys.contains($0) }
        for (group, names) in ThemeTokenCatalog.names {
            guard let table = file[group] as? [String: Any] else { continue }
            unknown += table.keys.filter { !names.contains($0) }.map { "\(group).\($0)" }
        }
        return unknown.sorted().map(ThemeError.unknownToken)
    }

    // MARK: Merging

    private static func decode(_ file: [String: Any], over base: [String: Any]) throws(ThemeError) -> Theme {
        let merged = overlay(file, on: base)
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else {
            preconditionFailure("A JSON object read from JSON can be written as JSON")
        }
        do {
            return try JSONDecoder().decode(Theme.self, from: data)
        } catch let error as DecodingError {
            throw describe(error)
        } catch {
            throw .malformedJSON(error.localizedDescription)
        }
    }

    /// `file` on top of `base`, key by key all the way down, so a file can change one field of one token.
    private static func overlay(_ file: [String: Any], on base: [String: Any]) -> [String: Any] {
        base.merging(file) { baseValue, fileValue in
            guard let baseTable = baseValue as? [String: Any], let fileTable = fileValue as? [String: Any] else {
                return fileValue
            }
            return overlay(fileTable, on: baseTable)
        }
    }

    private static func describe(_ error: DecodingError) -> ThemeError {
        func dotted(_ path: [any CodingKey]) -> String { path.map(\.stringValue).joined(separator: ".") }
        switch error {
        case .keyNotFound(let key, let context):
            return .invalidValue(path: dotted(context.codingPath + [key]), reason: "is missing.")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return .invalidValue(path: dotted(context.codingPath), reason: context.debugDescription)
        @unknown default:
            return .invalidValue(path: "", reason: String(describing: error))
        }
    }
}
