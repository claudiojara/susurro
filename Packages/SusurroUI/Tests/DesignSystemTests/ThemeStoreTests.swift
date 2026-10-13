import Foundation
import Testing

@testable import DesignSystem

/// A folder of theme files in the temporary directory, standing in for `Application Support/Susurro/Themes`.
private struct ThemesFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)")

    init(create: Bool = true) throws {
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }

    func write(_ name: String, _ text: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url.appendingPathComponent(name))
    }

    func writeTheme(_ id: String, spacingMD: Int) throws {
        try write("\(id).json", #"{"schemaVersion": 1, "spacing": {"md": \#(spacingMD)}}"#)
    }

    func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(name))
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func withThemes(_ body: (ThemesFolder) async throws -> Void) async throws {
    let folder = try ThemesFolder()
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

    @Test("a folder that does not exist yet has only the bundled theme, and files added later are found")
    func folderCreatedLater() async throws {
        let folder = try ThemesFolder(create: false)
        defer { folder.delete() }
        let store = ThemeStore(directory: folder.url)
        #expect(await store.themeIDs() == ["default"])
        #expect(await store.current == bundled)

        try folder.writeTheme("night", spacingMD: 14)
        await store.reload()
        #expect(await store.themeIDs() == ["default", "night"])
    }
}
