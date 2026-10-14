import Foundation

/// Holds the theme in use and tells observers when it changes.
///
/// The themes are the bundled one, named `default`, and every theme file in a folder (see `ThemeFiles`), named by its
/// file name without the extension (`default.json` is ignored). A new store has read nothing: it holds the bundled theme
/// and lists only that one, and construction does no file work on the caller's thread. `reload()` reads the folder, on a
/// background queue, and the app calls it at launch, so a folder that is slow to answer (a link to a network volume that
/// is not mounted) cannot hold the launch up. Nothing watches the folder here (see `ThemeFileWatcher`). A file that
/// cannot be used is published as the bundled theme together with its errors, so a mistake in a file being edited shows
/// up instead of leaving the old look.
///
/// At most `fileLimit` files are read, the first ones by name, and `folderErrors` says when there were more.
public actor ThemeStore {
    public static let defaultID = "default"
    /// The most theme files read from the folder. A folder of thousands of files would cost a read of each.
    public static let fileLimit = 64

    /// What reading the folder gave.
    struct Folder: Sendable {
        var themes: [String: ThemeLoadResult]
        /// Whether the folder had more theme files than `fileLimit`, which were left unread.
        var exceededLimit = false
    }

    /// The theme in use, with the errors of its file if it has any. Until the folder is read it is the bundled theme.
    public private(set) var current: ThemeLoadResult
    /// What is wrong with the folder as a whole, as opposed to one of its files: it has too many theme files.
    public private(set) var folderErrors: [ThemeError] = []

    private let directory: URL
    private let readFolder: @Sendable (URL) -> Folder
    private var activeID: String
    private var files: [String: ThemeLoadResult] = [:]
    private var hasReadFolder = false
    /// Numbers the reads in the order they began, so that a slow one cannot put older files over a newer read.
    private var readsBegun = 0
    private var newestReadApplied = 0
    private var observers: [Int: AsyncStream<ThemeLoadResult>.Continuation] = [:]
    private var observerCount = 0

    public init(directory: URL, activeID: String = ThemeStore.defaultID) {
        self.init(directory: directory, activeID: activeID, readFolder: ThemeStore.readFolder)
    }

    /// - Parameter readFolder: Reads the folder. It runs on a background queue, and never from this initializer.
    init(
        directory: URL, activeID: String = ThemeStore.defaultID, readFolder: @escaping @Sendable (URL) -> Folder
    ) {
        self.directory = directory
        self.activeID = activeID
        self.readFolder = readFolder
        current = ThemeLoadResult(theme: .default, errors: [])
    }

    /// `default` first, then the theme files by name.
    public func themeIDs() -> [String] {
        [Self.defaultID] + files.keys.sorted()
    }

    /// The theme in use now, then every change after it. The stream never finishes by itself. An observer that is slow
    /// to read gets the latest theme and skips the ones in between, since only the latest is worth showing.
    public func updates() -> AsyncStream<ThemeLoadResult> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ThemeLoadResult.self, bufferingPolicy: .bufferingNewest(1))
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

    /// Reads the folder, away from the caller's thread, and publishes the theme in use if it is different. The first
    /// call is what makes the files known. A read that finishes after a newer one has been applied is dropped.
    public func reload() async {
        readsBegun += 1
        let number = readsBegun
        let folder = await readOffTheCaller()
        guard number > newestReadApplied else { return }
        newestReadApplied = number
        files = folder.themes
        folderErrors = folder.exceededLimit ? [.tooManyThemeFiles(limit: Self.fileLimit)] : []
        hasReadFolder = true
        publishIfChanged()
    }

    /// Nothing is published until the folder has been read: what a chosen file holds is not known before.
    private func publishIfChanged() {
        guard hasReadFolder else { return }
        let next = Self.result(for: activeID, in: files)
        guard next != current else { return }
        current = next
        for observer in observers.values { observer.yield(next) }
    }

    /// A background queue and not the cooperative pool, since reading may wait on a slow disk or network volume.
    private func readOffTheCaller() async -> Folder {
        let directory = directory
        let readFolder = readFolder
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: readFolder(directory)) }
        }
    }

    private func removeObserver(_ id: Int) {
        observers[id] = nil
    }

    private static func result(for id: String, in files: [String: ThemeLoadResult]) -> ThemeLoadResult {
        if id == defaultID { return ThemeLoadResult(theme: .default, errors: []) }
        return files[id] ?? ThemeLoadResult(theme: .default, errors: [.themeNotFound(id)])
    }

    /// A folder that is missing or cannot be listed has no themes.
    private static func readFolder(_ directory: URL) -> Folder {
        let (urls, hasMore) = ThemeFiles.firstURLs(in: directory, limit: fileLimit)
        var themes: [String: ThemeLoadResult] = [:]
        for url in urls {
            let id = url.deletingPathExtension().lastPathComponent
            if id != defaultID { themes[id] = ThemeLoader.load(contentsOf: url) }
        }
        return Folder(themes: themes, exceededLimit: hasMore)
    }
}
