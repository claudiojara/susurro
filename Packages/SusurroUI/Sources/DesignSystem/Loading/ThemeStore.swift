import Foundation

/// Holds the theme in use and tells observers when it changes.
///
/// The themes are the bundled one, named `default`, and every `*.json` file in a folder, named by its file name without
/// the extension (`default.json` is ignored). The store loads the files when it is created and again on `reload()`;
/// nothing watches the folder here (see `ThemeFileWatcher`). A file that cannot be used is published as the bundled
/// theme together with its errors, so a mistake in a file being edited shows up instead of leaving the old look.
public actor ThemeStore {
    public static let defaultID = "default"

    /// The theme in use, with the errors of its file if it has any.
    public private(set) var current: ThemeLoadResult

    private let directory: URL
    private var activeID: String
    private var files: [String: ThemeLoadResult]
    private var observers: [Int: AsyncStream<ThemeLoadResult>.Continuation] = [:]
    private var observerCount = 0

    public init(directory: URL, activeID: String = ThemeStore.defaultID) {
        let files = Self.load(directory)
        self.directory = directory
        self.activeID = activeID
        self.files = files
        current = Self.result(for: activeID, in: files)
    }

    /// `default` first, then the theme files by name.
    public func themeIDs() -> [String] {
        [Self.defaultID] + files.keys.sorted()
    }

    /// The theme in use now, then every change after it. The stream never finishes by itself.
    public func updates() -> AsyncStream<ThemeLoadResult> {
        let (stream, continuation) = AsyncStream.makeStream(of: ThemeLoadResult.self, bufferingPolicy: .unbounded)
        observerCount += 1
        let id = observerCount
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        continuation.yield(current)
        return stream
    }

    /// Uses another theme. An id that names no theme gives the bundled theme and an error.
    public func select(_ id: String) {
        activeID = id
        publishIfChanged()
    }

    /// Reads the folder again. Observers hear of it only if the theme in use is different.
    public func reload() {
        files = Self.load(directory)
        publishIfChanged()
    }

    private func publishIfChanged() {
        let next = Self.result(for: activeID, in: files)
        guard next != current else { return }
        current = next
        for observer in observers.values { observer.yield(next) }
    }

    private func removeObserver(_ id: Int) {
        observers[id] = nil
    }

    private static func result(for id: String, in files: [String: ThemeLoadResult]) -> ThemeLoadResult {
        if id == defaultID { return ThemeLoadResult(theme: .default, errors: []) }
        return files[id] ?? ThemeLoadResult(theme: .default, errors: [.themeNotFound(id)])
    }

    /// A folder that is missing or cannot be listed has no themes.
    private static func load(_ directory: URL) -> [String: ThemeLoadResult] {
        let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        var files: [String: ThemeLoadResult] = [:]
        for url in urls ?? [] where url.pathExtension.lowercased() == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            if id != defaultID { files[id] = ThemeLoader.load(contentsOf: url) }
        }
        return files
    }
}
