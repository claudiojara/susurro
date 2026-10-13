#if DEBUG
    import Foundation
    import Testing

    @testable import DesignSystem

    /// These tests use the real file system and wait for real events, so they poll, with a long limit that a passing
    /// run never reaches.
    @Suite("Theme file watcher")
    struct ThemeFileWatcherTests {
        private actor Calls {
            private(set) var count = 0
            func record() { count += 1 }
        }

        private let debounce = Duration.milliseconds(40)

        private func makeFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("watched-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func eventually(_ condition: () async -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                if await condition() { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }

        private func theme(spacingMD: Int) -> Data {
            Data(#"{"schemaVersion": 1, "spacing": {"md": \#(spacingMD)}}"#.utf8)
        }

        @Test("it reports a theme file that is added")
        func reportsAnAddedFile() async throws {
            let folder = try makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let calls = Calls()
            let watcher = ThemeFileWatcher(directory: folder, debounce: debounce) { await calls.record() }
            await watcher.start()
            try theme(spacingMD: 14).write(to: folder.appendingPathComponent("night.json"))
            #expect(await eventually { await calls.count >= 1 })
            await watcher.stop()
        }

        @Test("it reports a file edited in place, then a second edit of the same file")
        func reportsEditsInPlace() async throws {
            let folder = try makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("night.json")
            try theme(spacingMD: 14).write(to: file)
            let calls = Calls()
            let watcher = ThemeFileWatcher(directory: folder, debounce: debounce) { await calls.record() }
            await watcher.start()

            try theme(spacingMD: 15).write(to: file)
            #expect(await eventually { await calls.count >= 1 })
            try theme(spacingMD: 16).write(to: file)
            #expect(await eventually { await calls.count >= 2 })
            await watcher.stop()
        }

        @Test("it reports a file that is removed, and a file that replaces another")
        func reportsRemovalAndReplacement() async throws {
            let folder = try makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("night.json")
            try theme(spacingMD: 14).write(to: file)
            let calls = Calls()
            let watcher = ThemeFileWatcher(directory: folder, debounce: debounce) { await calls.record() }
            await watcher.start()

            try theme(spacingMD: 15).write(to: file, options: .atomic)
            #expect(await eventually { await calls.count >= 1 })
            try FileManager.default.removeItem(at: file)
            #expect(await eventually { await calls.count >= 2 })
            await watcher.stop()
        }

        @Test("it reports nothing after it is stopped")
        func stops() async throws {
            let folder = try makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let calls = Calls()
            let watcher = ThemeFileWatcher(directory: folder, debounce: debounce) { await calls.record() }
            await watcher.start()
            await watcher.stop()
            try theme(spacingMD: 14).write(to: folder.appendingPathComponent("night.json"))
            try await Task.sleep(for: debounce * 10)
            #expect(await calls.count == 0)
        }

        @Test("a save that empties the file and then writes it is one change, and the store never sees the empty file")
        func coalescesASave() async throws {
            let folder = try makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("night.json")
            try theme(spacingMD: 14).write(to: file)
            let store = ThemeStore(directory: folder, activeID: "night")
            var updates = await store.updates().makeAsyncIterator()
            _ = await updates.next()
            let watcher = ThemeFileWatcher(directory: folder, debounce: .milliseconds(300)) { await store.reload() }
            await watcher.start()

            try Data().write(to: file)
            try theme(spacingMD: 16).write(to: file)
            #expect(await eventually { await store.current.theme.spacing["md"] == 16 })
            let published = await updates.next()
            #expect(published?.theme.spacing["md"] == 16)
            #expect(published?.errors == [])
            await watcher.stop()
        }
    }
#endif
