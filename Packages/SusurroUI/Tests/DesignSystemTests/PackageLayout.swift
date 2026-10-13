import Foundation

/// Where the files of the `SusurroUI` package are, found from this source file so that a test can read them whatever
/// the working directory is.
enum PackageLayout {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DesignSystemTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the package

    /// The repository: the folder that holds `Packages` and `.github`.
    static let repository =
        root
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // the repository

    static func repositoryFile(_ path: String) -> URL {
        repository.appendingPathComponent(path)
    }

    static func sources(_ target: String) -> URL {
        root.appendingPathComponent("Sources").appendingPathComponent(target)
    }

    static func fixture(_ name: String) -> URL {
        root.appendingPathComponent("Tests/DesignSystemTests/Fixtures").appendingPathComponent(name)
    }
}
