import Foundation
import Testing

@testable import DesignSystem

private func withThemes(_ body: (ScratchFolder) async throws -> Void) async throws {
    let folder = try ScratchFolder()
    defer { folder.delete() }
    try await body(folder)
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
            let store = ThemeStore(directory: folder.url)
            #expect(await store.themeIDs() == ["default", "dawn", "night"])
            #expect(await store.current == bundled)
        }
    }

    @Test("it starts on the bundled theme unless told which file to use")
    func startsOnTheChosenTheme() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            #expect(await ThemeStore(directory: folder.url).current == bundled)
            let night = await ThemeStore(directory: folder.url, activeID: "night").current
            #expect(night.theme.spacing["md"] == 14)
            #expect(night.errors == [])
        }
    }

    @Test("replacing the active file and reloading publishes the new theme to every observer")
    func reloadPublishesTheNewTheme() async throws {
        try await withThemes { folder in
            try folder.writeTheme("night", spacingMD: 14)
            let store = ThemeStore(directory: folder.url, activeID: "night")
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
            let store = ThemeStore(directory: folder.url, activeID: "night")
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
            let store = ThemeStore(directory: folder.url, activeID: "night")
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
            let store = ThemeStore(directory: folder.url, activeID: "night")
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
            let store = ThemeStore(directory: folder.url)
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
            let store = ThemeStore(directory: folder.url, activeID: "night")
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

            let store = ThemeStore(directory: folder.url, activeID: "alias")
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
        let store = ThemeStore(directory: folder.url)
        #expect(await store.themeIDs() == ["default"])
        #expect(await store.current == bundled)

        try folder.writeTheme("night", spacingMD: 14)
        await store.reload()
        #expect(await store.themeIDs() == ["default", "night"])
    }
}
