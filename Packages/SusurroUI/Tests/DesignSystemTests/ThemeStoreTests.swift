import Foundation
import Synchronization
import Testing

@testable import DesignSystem

private func withThemes(_ body: (ScratchFolder) async throws -> Void) async throws {
    let folder = try ScratchFolder()
    defer { folder.delete() }
    try await body(folder)
}

/// A store with its folder read, as the app has it once it has launched.
private func loadedStore(_ folder: ScratchFolder, activeID: String = ThemeStore.defaultID) async -> ThemeStore {
    let store = ThemeStore(directory: folder.url, activeID: activeID)
    await store.reload()
    return store
}

/// Counts the reads of a folder and keeps the thread of each, in place of the store's own reading.
private final class FolderReads: Sendable {
    private struct State {
        var threads: [Bool] = []
        var gates: [DispatchSemaphore] = []
    }
    private let state = Mutex(State())
    private let results: [ThemeStore.Folder]
    private let blocking: Set<Int>

    /// `results` are answered in the order of the reads; a read whose number is in `blocking` waits for `release(_:)`.
    init(results: [ThemeStore.Folder], blocking: Set<Int> = []) {
        self.results = results
        self.blocking = blocking
    }

    var count: Int { state.withLock { $0.threads.count } }
    /// Whether each read ran on the main thread.
    var onMainThread: [Bool] { state.withLock { $0.threads } }

    func read(_ directory: URL) -> ThemeStore.Folder {
        let (number, gate) = state.withLock { state in
            state.threads.append(Thread.isMainThread)
            let number = state.threads.count - 1
            let gate = DispatchSemaphore(value: 0)
            state.gates.append(gate)
            return (number, gate)
        }
        if blocking.contains(number) { gate.wait() }
        return results[min(number, results.count - 1)]
    }

    func release(_ number: Int) {
        let gate = state.withLock { $0.gates[number] }
        gate.signal()
    }
}

@Suite("Theme store")
struct ThemeStoreTests {
    private let bundled = ThemeLoadResult(theme: .default, errors: [])

    @Test("it lists the bundled theme first, then every JSON file by name, and ignores other files")
    func listsThemes() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            try folder.writeTheme("dawn", spacingMD: 15)
            try folder.writeTheme("default", spacingMD: 99)
            try folder.write("notes.txt", "not a theme")
            let store = await loadedStore(folder)
            #expect(await store.themeIDs() == ["default", "dawn", "night"])
            #expect(await store.current == bundled)
        }
    }

    @Test("it starts on the bundled theme unless told which file to use")
    func startsOnTheChosenTheme() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            #expect(await loadedStore(folder).current == bundled)
            let night = await loadedStore(folder, activeID: "night").current
            #expect(night.theme.spacing["md"] == 14)
            #expect(night.errors == [])
        }
    }

    @Test("replacing the active file and reloading publishes the new theme to every observer")
    func reloadPublishesTheNewTheme() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder, activeID: "night")
            var first = await store.updates().makeAsyncIterator()
            var second = await store.updates().makeAsyncIterator()
            #expect(await first.next()?.theme.spacing["md"] == 14)
            #expect(await second.next()?.theme.spacing["md"] == 14)

            try folder.writeTheme("night", spacingMD: 16)
            await store.reload()
            #expect(await first.next()?.theme.spacing["md"] == 16)
            #expect(await second.next()?.theme.spacing["md"] == 16)
            #expect(await store.current.theme.spacing["md"] == 16)
        }
    }

    @Test("a reload that changes nothing publishes nothing")
    func unchangedReloadIsSilent() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder, activeID: "night")
            var updates = await store.updates().makeAsyncIterator()
            _ = await updates.next()
            await store.reload()
            try folder.writeTheme("night", spacingMD: 16)
            await store.reload()
            #expect(await updates.next()?.theme.spacing["md"] == 16)
        }
    }

    @Test("a broken file publishes the default theme with its errors, and a fixed one recovers")
    func brokenFileThenFixed() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder, activeID: "night")
            var updates = await store.updates().makeAsyncIterator()
            _ = await updates.next()

            try folder.write("night.json", #"{"schemaVersion": 1, "spacing": {"huge": 40}}"#)
            await store.reload()
            let broken = await updates.next()
            #expect(broken?.theme == .default)
            #expect(broken?.errors == [.unknownToken("spacing.huge")])

            try folder.writeTheme("night", spacingMD: 18)
            await store.reload()
            let fixed = await updates.next()
            #expect(fixed?.theme.spacing["md"] == 18)
            #expect(fixed?.errors == [])
        }
    }

    @Test("a deleted active file falls back to the bundled theme and says it is gone")
    func deletedFile() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder, activeID: "night")
            try folder.remove("night.json")
            await store.reload()
            #expect(await store.current == ThemeLoadResult(theme: .default, errors: [.themeNotFound("night")]))
            #expect(await store.themeIDs() == ["default"])
        }
    }

    @Test("selecting a theme publishes it, and selecting an unknown one publishes the default with an error")
    func selecting() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder)
            var updates = await store.updates().makeAsyncIterator()
            #expect(await updates.next() == bundled)

            await store.select("night")
            #expect(await updates.next()?.theme.spacing["md"] == 14)
            await store.select("nowhere")
            #expect(await updates.next() == ThemeLoadResult(theme: .default, errors: [.themeNotFound("nowhere")]))
            await store.select("default")
            #expect(await updates.next() == bundled)
        }
    }

    @Test("an observer that falls behind is told only the latest theme")
    func stalledObserver() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = await loadedStore(folder, activeID: "night")
            var stalled = await store.updates().makeAsyncIterator()
            for md in [15, 16, 17] {
                try folder.writeTheme("night", spacingMD: md)
                await store.reload()
            }
            #expect(await stalled.next()?.theme.spacing["md"] == 17)

            // Had older results been kept, this would still be 15 or 16.
            try folder.writeTheme("night", spacingMD: 18)
            await store.reload()
            #expect(await stalled.next()?.theme.spacing["md"] == 18)
        }
    }

    @Test("it lists regular files and links to them, not pipes or folders, and reports a file over the size cap")
    func listsOnlyRegularFiles() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            try folder.makeSymlink("alias.json", to: folder.file("night.json"))
            try folder.makeFIFO("pipe.json")
            try folder.makeFolder("folder.json")
            try folder.makeSymlink("alias-of-pipe.json", to: folder.file("pipe.json"))
            try folder.write("huge.json", themeText(ofSize: ThemeFiles.sizeLimit + 1))

            let store = await loadedStore(folder, activeID: "alias")
            #expect(await store.themeIDs() == ["default", "alias", "huge", "night"])
            #expect(await store.current.theme.spacing["md"] == 14)
            #expect(await store.current.errors == [])

            await store.select("huge")
            #expect(
                await store.current
                    == ThemeLoadResult(
                        theme: .default, errors: [.unreadable(file: "huge.json", reason: "It is larger than 256 KB.")]))
        }
    }

    @Test("a folder that does not exist yet has only the bundled theme, and files added later are found")
    func folderCreatedLater() async throws {
        let folder = try ScratchFolder(create: false)
        defer { folder.delete() }
        let store = await loadedStore(folder)
        #expect(await store.themeIDs() == ["default"])
        #expect(await store.current == bundled)

        try folder.writeTheme("night", spacingMD: 14)
        await store.reload()
        #expect(await store.themeIDs() == ["default", "night"])
    }

    // MARK: Reading the folder

    @Test("a new store reads nothing: it holds the bundled theme and lists only that one until it is told to read")
    func constructionReadsNothing() async throws {
        let reads = FolderReads(results: [ThemeStore.Folder(themes: ["night": bundled])])

        let store = ThemeStore(directory: URL(filePath: "/nowhere"), activeID: "night", readFolder: reads.read)

        #expect(reads.count == 0)
        #expect(await store.current == bundled)
        #expect(await store.themeIDs() == ["default"])
        #expect(await store.folderErrors.isEmpty)
        #expect(reads.count == 0)
    }

    @Test("the folder is read away from the caller's thread, once for each reload")
    @MainActor
    func readsOffTheCaller() async {
        let reads = FolderReads(results: [ThemeStore.Folder(themes: [:])])
        let store = ThemeStore(directory: URL(filePath: "/nowhere"), readFolder: reads.read)

        await store.reload()
        await store.reload()

        #expect(reads.onMainThread == [false, false])
    }

    @Test("until the folder is read, a chosen file theme is pending: the bundled theme shows, with no error")
    func pendingThemeShowsNoError() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = ThemeStore(directory: folder.url, activeID: "night")
            var updates = await store.updates().makeAsyncIterator()
            let before = await updates.next()

            await store.select("night")
            let afterSelecting = await store.current
            await store.reload()
            let loaded = await updates.next()

            #expect(before == bundled)
            #expect(afterSelecting == bundled)
            #expect(loaded?.theme.spacing["md"] == 14)
            #expect(loaded?.errors == [])
        }
    }

    @Test("a theme chosen before the folder is read is shown once it is, or reported missing when it is not there")
    func choiceBeforeTheFirstRead() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = ThemeStore(directory: folder.url)
            await store.select("night")
            await store.reload()
            #expect(await store.current.theme.spacing["md"] == 14)

            let other = ThemeStore(directory: folder.url)
            await other.select("nowhere")
            await other.reload()
            #expect(await other.current == ThemeLoadResult(theme: .default, errors: [.themeNotFound("nowhere")]))
        }
    }

    @Test("a slow read that finishes after a newer one does not put its older files over them", .timeLimit(.minutes(1)))
    func slowReadIsDropped() async {
        let older = ThemeStore.Folder(themes: ["old": bundled])
        let newer = ThemeStore.Folder(themes: ["new": bundled])
        let reads = FolderReads(results: [older, newer], blocking: [0])
        let store = ThemeStore(directory: URL(filePath: "/nowhere"), readFolder: reads.read)

        let slow = Task { await store.reload() }
        while reads.count < 1 { await Task.yield() }
        await store.reload()
        let afterTheNewer = await store.themeIDs()
        reads.release(0)
        await slow.value

        #expect(afterTheNewer == ["default", "new"])
        #expect(await store.themeIDs() == ["default", "new"])
    }

    // MARK: The cap on files

    @Test("a folder with as many theme files as the cap is read whole, and one more is cut with an error")
    func fileCap() async throws {
        try await withThemes { folder in
            let limit = ThemeStore.fileLimit
            for number in 0..<limit { try folder.writeTheme(String(format: "t%03d", number), spacingMD: 14) }
            let atTheCap = await loadedStore(folder)
            let namesAtTheCap = await atTheCap.themeIDs()
            let errorsAtTheCap = await atTheCap.folderErrors

            try folder.writeTheme("t999", spacingMD: 14)
            let pastTheCap = await loadedStore(folder)
            let namesPast = await pastTheCap.themeIDs()
            let errorsPast = await pastTheCap.folderErrors

            #expect(limit == 64)
            #expect(namesAtTheCap.count == limit + 1)
            #expect(errorsAtTheCap.isEmpty)
            #expect(namesPast.count == limit + 1)
            #expect(namesPast.contains("t999") == false)
            #expect(namesPast.last == "t063")
            #expect(errorsPast == [.tooManyThemeFiles(limit: limit)])
        }
    }

    @Test("the error goes when the folder is back under the cap")
    func capErrorClears() async throws {
        try await withThemes { folder in
            for number in 0..<(ThemeStore.fileLimit + 3) {
                try folder.writeTheme(String(format: "t%03d", number), spacingMD: 14)
            }
            let store = await loadedStore(folder)
            let whileOver = await store.folderErrors

            for number in 0..<4 { try folder.remove(String(format: "t%03d.json", number)) }
            await store.reload()

            #expect(whileOver == [.tooManyThemeFiles(limit: ThemeStore.fileLimit)])
            #expect(await store.folderErrors.isEmpty)
            #expect(await store.themeIDs().count == ThemeStore.fileLimit + 3 - 4 + 1)  // 63 files and the bundled theme
        }
    }
}
