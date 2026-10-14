import Foundation

/// The atoms, found by reading `Sources/DesignSystem/Atoms`: a public struct that is a `View`. A list kept by hand would
/// leave out the atom that someone forgot to add to it, which is the atom these tests are for.
enum AtomSources {
    struct Atom {
        let name: String
        let file: URL
        let source: String
        /// The `public init(...)` signatures, each as one text.
        var initializers: [String] {
            source.matches(of: /public init\([^{]*\{/).map { String($0.output) }
        }
    }

    static let folder = PackageLayout.sources("DesignSystem").appendingPathComponent("Atoms")

    static func atoms() throws -> [Atom] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { file in
            guard file.pathExtension == "swift" else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            guard let match = source.firstMatch(of: /public struct (\w+)\s*:\s*View/) else { return nil }
            return Atom(name: String(match.output.1), file: file, source: source)
        }
    }

    static func text(of file: String, in folder: URL = AtomSources.folder) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }

    static let tests = PackageLayout.root.appendingPathComponent("Tests/DesignSystemTests/Atoms")
}
