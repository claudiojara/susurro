import Foundation

/// What loading a theme file gave. `errors` is empty when the file was used. Otherwise `theme` is the bundled default
/// and `errors` lists the problems that were found in the file, so they can be shown or logged.
public nonisolated struct ThemeLoadResult: Sendable, Equatable {
    public let theme: Theme
    public let errors: [ThemeError]
}

/// Reads a theme file and merges it onto the bundled default, key by key, so a file lists only what it changes. A file
/// that cannot be used as a whole is rejected as a whole: loading never returns a theme that is half applied.
///
/// When a file is rejected, the errors say everything wrong with its contents, not only the first: unknown keys, bad
/// values, colors that point at a missing palette entry, and numbers out of range, together, in that order. Three
/// things stop the report early because nothing past them can be read: text that is not a JSON object, a file that
/// cannot be read (see `ThemeFiles`), and a missing or unsupported `schemaVersion`, which is checked alone since a file
/// of another version may have another shape. A file with more than 50 bad values is reported for the first 50 it
/// meets.
///
/// Loading is `nonisolated`, so a caller can read and decode files away from the main actor.
public nonisolated enum ThemeLoader {
    /// A file with more bad values than this is reported for the first ones it meets.
    static let valueErrorLimit = 50

    public static func load(contentsOf url: URL) -> ThemeLoadResult {
        do throws(ThemeError) {
            return load(data: try ThemeFiles.contents(of: url))
        } catch {
            return rejected([error])
        }
    }

    public static func load(data: Data) -> ThemeLoadResult {
        var file: [String: Any]
        do throws(ThemeError) {
            file = try parseObject(data)
            try checkVersion(of: file)
        } catch {
            return rejected([error])
        }

        // Keys the theme does not use are reported and left out, so they cannot cause a second error about themselves.
        let unknown = unknownKeys(in: file)
        for path in unknown { drop(path[...], from: &file) }
        var badValues = removeNonFinite(from: &file)
        let (theme, failures) = decode(file)
        badValues += failures

        var errors = unknown.map { ThemeError.unknownToken($0.joined(separator: ".")) }
        errors += badValues.sorted { $0.path < $1.path }.map(\.error)
        if let theme { errors += problems(of: theme, in: file) }
        guard errors.isEmpty, let theme else { return rejected(errors) }
        return ThemeLoadResult(theme: theme, errors: [])
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

    private static let fileKeys = Set(["schemaVersion", "name", "palette"] + ThemeTokenCatalog.groups.map(\.name))

    /// The paths of the keys the file has that the theme does not use: groups, tokens, and the fields of a token or of
    /// a palette color. Decoding would skip them without a word.
    private static func unknownKeys(in file: [String: Any]) -> [[String]] {
        var unknown = file.keys.filter { !fileKeys.contains($0) }.map { [$0] }
        for group in ThemeTokenCatalog.groups {
            guard let table = file[group.name] as? [String: Any] else { continue }
            for (token, value) in table {
                if !group.expected.contains(token) {
                    unknown.append([group.name, token])
                } else if !group.fields.isEmpty, let object = value as? [String: Any] {
                    unknown += object.keys.filter { !group.fields.contains($0) }.map { [group.name, token, $0] }
                }
            }
        }
        for (name, value) in file["palette"] as? [String: Any] ?? [:] {
            guard let color = value as? [String: Any] else { continue }
            unknown += color.keys.filter { !ThemeTokenCatalog.paletteFields.contains($0) }.map {
                ["palette", name, $0]
            }
        }
        return unknown.sorted { $0.joined(separator: ".") < $1.joined(separator: ".") }
    }

    /// `-1e999` is read as minus infinity, which cannot be written back out as JSON to be decoded: it traps. So a
    /// number that is not finite, anywhere in the file, is taken out of it here, and reported. A number inside a list
    /// is reported at the list, which is taken out whole.
    private static func removeNonFinite(from file: inout [String: Any]) -> [BadValue] {
        var found: [(path: [String], number: Double)] = []
        func walk(_ value: Any, _ path: [String]) {
            if let table = value as? [String: Any] {
                for (key, inner) in table { walk(inner, path + [key]) }
            } else if let list = value as? [Any] {
                for inner in list { walk(inner, path) }
            } else if let number = value as? NSNumber, !number.doubleValue.isFinite,
                !found.contains(where: { $0.path == path })
            {
                found.append((path, number.doubleValue))
            }
        }
        walk(file, [])
        for (path, _) in found { drop(path[...], from: &file) }
        return found.map { path, number in
            BadValue(path: path, error: { .notAllowed(number, at: $0) })
        }
    }

    /// The problems of a theme that decoded: tokens it lacks, colors that point nowhere, numbers out of range.
    /// A color that points at a palette entry the file wrote is not reported, even though the entry was bad: its own
    /// error says what to fix.
    private static func problems(of theme: Theme, in file: [String: Any]) -> [ThemeError] {
        let written = Set((file["palette"] as? [String: Any])?.keys.map { $0 } ?? [])
        return theme.problems().filter { error in
            if case .missingPaletteKey(_, let paletteKey) = error { return !written.contains(paletteKey) }
            return true
        }
    }

    // MARK: Decoding

    private struct BadValue {
        let path: String
        let error: ThemeError

        init(path: [String], error: (String) -> ThemeError) {
            self.path = path.joined(separator: ".")
            self.error = error(self.path)
        }
    }

    /// Decodes `file` over the bundled theme. A value that does not decode is reported and taken out of the file, so
    /// the next pass can find the next one: the decoder stops at the first, and this goes on until it has seen them
    /// all, or `valueErrorLimit` of them, since each pass reads the whole file again. The theme is nil if it stopped
    /// early.
    private static func decode(_ file: [String: Any]) -> (theme: Theme?, failures: [BadValue]) {
        let base = Theme.bundledObject
        var remaining = file
        var failures: [BadValue] = []
        while failures.count < valueErrorLimit {
            let merged = overlay(remaining, on: base)
            guard JSONSerialization.isValidJSONObject(merged),
                let data = try? JSONSerialization.data(withJSONObject: merged)
            else { preconditionFailure("A JSON object without infinite numbers can be written as JSON") }
            do {
                return (try JSONDecoder().decode(Theme.self, from: data), failures)
            } catch let error as DecodingError {
                let (path, reason) = describe(error)
                failures.append(BadValue(path: path, error: { .invalidValue(path: $0, reason: reason) }))
                guard repair(&remaining, at: path, base: base) else { return (nil, failures) }
            } catch {
                failures.append(BadValue(path: [], error: { _ in .malformedJSON(error.localizedDescription) }))
                return (nil, failures)
            }
        }
        return (nil, failures)
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

    private static func describe(_ error: DecodingError) -> (path: [String], reason: String) {
        switch error {
        case .keyNotFound(let key, let context):
            return ((context.codingPath + [key]).map(\.stringValue), "is missing.")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return (context.codingPath.map(\.stringValue), context.debugDescription)
        @unknown default:
            return ([], String(describing: error))
        }
    }

    // MARK: Editing the tree

    /// What stands in for a bad or missing part of a palette color the bundled theme does not have, so that the
    /// color's other part is still checked. Only palette colors are named by a file; every other value has a bundled
    /// one to fall back on.
    private static let placeholderColor = RGBAColor.placeholder.hex

    /// Takes the value at `path` out of the way so the merge can go on, and says whether it could.
    ///
    /// A value the bundled theme also has is removed, and the merge falls back to the bundled one. A part of a palette
    /// color the bundled theme does not have is replaced by a placeholder. A whole such color is removed.
    private static func repair(_ tree: inout [String: Any], at path: [String], base: [String: Any]?) -> Bool {
        guard let key = path.first else { return false }
        if path.count == 1 {
            if base == nil {
                tree[key] = placeholderColor
                return true
            }
            return tree.removeValue(forKey: key) != nil
        }
        guard var child = tree[key] as? [String: Any],
            repair(&child, at: Array(path.dropFirst()), base: base?[key] as? [String: Any])
        else { return false }
        tree[key] = child
        return true
    }

    /// Removes exactly the value at `path`, if the file has it.
    private static func drop(_ path: ArraySlice<String>, from tree: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            tree[key] = nil
        } else if var child = tree[key] as? [String: Any] {
            drop(path.dropFirst(), from: &child)
            tree[key] = child
        }
    }
}
