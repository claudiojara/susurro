#if DEBUG
    import Foundation
    import Testing

    @testable import DesignSystem

    /// The watcher waits through an injected `sleep`, and these tests hold it in a `ManualSleeper`: a debounce or a
    /// retry ends when the test fires it, not when a clock says so, so no test depends on how fast the machine is. The
    /// file system events are real, so a test that starts from one waits for it to arrive (see `eventually`); once it
    /// has, everything after is decided by the test.
    ///
    /// A save is exact: one `onChange` per save. The watcher drops events from sources it has replaced, and a new
    /// source sees nothing from before it was opened, so no event of an earlier save can start a call for a later
    /// one.
    @Suite("Theme file watcher")
    struct ThemeFileWatcherTests {
        private static let debounce = Duration.milliseconds(40)
        private static let retry = Duration.milliseconds(70)

        private final class Harness: Sendable {
            let folder: ScratchFolder
            let sleeper = ManualSleeper()
            let calls = Counter()
            let watcher: ThemeFileWatcher

            init(folder: ScratchFolder) {
                self.folder = folder
                let (sleeper, calls) = (sleeper, calls)
                watcher = ThemeFileWatcher(
                    directory: folder.url, debounce: ThemeFileWatcherTests.debounce,
                    retryInterval: ThemeFileWatcherTests.retry, sleep: { try await sleeper.sleep($0) },
                    onChange: { calls.record() })
            }

            /// Ends the debounce each time the watcher has one, until `onChange` has been called `count` times. It
            /// never goes past `count`: an extra call would make this wait for 10 seconds and fail.
            func waitForCalls(_ count: Int) async -> Bool {
                await eventually {
                    sleeper.fire(ThemeFileWatcherTests.debounce)
                    return calls.count == count
                }
            }

            var debounceIsWaiting: Bool { sleeper.waiting(ThemeFileWatcherTests.debounce) > 0 }
        }

        private func withWatcher(createFolder: Bool = true, _ body: (Harness) async throws -> Void) async throws {
            let harness = Harness(folder: try ScratchFolder(create: createFolder))
            defer { harness.folder.delete() }
            do {
                try await body(harness)
            } catch {
                await harness.watcher.stop()
                throw error
            }
            await harness.watcher.stop()
        }

        // MARK: Real events

        @Test("it reports a theme file that is added, once")
        func reportsAnAddedFile() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                try watched.folder.writeTheme("night", spacingMD: 14)
                #expect(await watched.waitForCalls(1))
                #expect(watched.sleeper.waiting(Self.debounce) == 0)
            }
        }

        @Test("it reports a file edited in place, then a second edit of the same file, once each")
        func reportsEditsInPlace() async throws {
            try await withWatcher { watched in
                try watched.folder.writeTheme("night", spacingMD: 14)
                await watched.watcher.start()

                try watched.folder.writeTheme("night", spacingMD: 15)
                #expect(await watched.waitForCalls(1))
                try watched.folder.writeTheme("night", spacingMD: 16)
                #expect(await watched.waitForCalls(2))
                #expect(watched.sleeper.waiting(Self.debounce) == 0)
            }
        }

        @Test("it reports a file that replaces another, an edit of the replacement, and its removal, once each")
        func reportsReplacementThenEditThenRemoval() async throws {
            try await withWatcher { watched in
                try watched.folder.writeTheme("night", spacingMD: 14)
                await watched.watcher.start()

                try Data(#"{"schemaVersion": 1, "spacing": {"md": 15}}"#.utf8)
                    .write(to: watched.folder.file("night.json"), options: .atomic)
                #expect(await watched.waitForCalls(1))
                try watched.folder.writeTheme("night", spacingMD: 16)
                #expect(await watched.waitForCalls(2))
                try watched.folder.remove("night.json")
                #expect(await watched.waitForCalls(3))
                #expect(watched.sleeper.waiting(Self.debounce) == 0)
            }
        }

        @Test("a save that empties the file and then writes it is one change, and the store reads only the final file")
        func coalescesASave() async throws {
            try await withWatcher { watched in
                try watched.folder.writeTheme("night", spacingMD: 14)
                let store = ThemeStore(directory: watched.folder.url, activeID: "night")
                var updates = await store.updates().makeAsyncIterator()
                _ = await updates.next()
                let sleeper = watched.sleeper
                let watcher = ThemeFileWatcher(
                    directory: watched.folder.url, debounce: Self.debounce, retryInterval: Self.retry,
                    sleep: { try await sleeper.sleep($0) }
                ) { await store.reload() }
                await watcher.start()

                // The wait is still open between the two writes, so nothing reads the folder while the file is empty.
                try Data().write(to: watched.folder.file("night.json"))
                #expect(await eventually { sleeper.waiting(Self.debounce) > 0 })
                try watched.folder.writeTheme("night", spacingMD: 16)
                #expect(
                    await eventually {
                        sleeper.fire(Self.debounce)
                        return await store.current.theme.spacing["md"] == 16
                    })

                // The first result observers got is the final one: no result for the empty file came before it.
                let published = await updates.next()
                #expect(published?.theme.spacing["md"] == 16)
                #expect(published?.errors == [])
                await watcher.stop()
            }
        }

        // MARK: Stopping

        @Test("it reports nothing after it is stopped, while a watcher left running does")
        func stops() async throws {
            try await withWatcher { watched in
                let other = Harness(folder: watched.folder)
                await watched.watcher.start()
                await other.watcher.start()
                await watched.watcher.stop()
                try watched.folder.writeTheme("night", spacingMD: 14)
                // The event is real: the watcher that was left running has seen it, so it did arrive.
                #expect(await eventually { other.debounceIsWaiting })
                await letTasksRun()
                #expect(watched.sleeper.waiting(Self.debounce) == 0)
                #expect(watched.calls.count == 0)
                #expect(await other.waitForCalls(1))
                await other.watcher.stop()
            }
        }

        @Test("stopping while a debounce is pending cancels it, and nothing is reported")
        func stopWhilePending() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                try watched.folder.writeTheme("night", spacingMD: 14)
                #expect(await eventually { watched.debounceIsWaiting })

                await watched.watcher.stop()
                #expect(watched.sleeper.waiting(Self.debounce) == 0)
                watched.sleeper.fire(Self.debounce)
                await letTasksRun()
                #expect(watched.calls.count == 0)
                #expect(await watched.watcher.state == .stopped)
            }
        }

        // MARK: Debounce, with events given directly

        @Test("a save that shows up as several events is one call, and the next save is another")
        func burstIsOneCall() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                for _ in 1...3 { await watched.watcher.noteChange() }
                #expect(await eventually { watched.debounceIsWaiting })
                await letTasksRun()
                #expect(watched.sleeper.waiting(Self.debounce) == 1)
                #expect(watched.sleeper.cancelled == 2)

                watched.sleeper.fire(Self.debounce)
                #expect(await eventually { watched.calls.count == 1 })
                await letTasksRun()
                #expect(watched.calls.count == 1)
                #expect(watched.sleeper.waiting(Self.debounce) == 0)

                await watched.watcher.noteChange()
                #expect(await watched.waitForCalls(2))
            }
        }

        @Test("each event starts the wait again, so the call comes after the last event")
        func eachEventRestartsTheWait() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                await watched.watcher.noteChange()
                #expect(await eventually { watched.sleeper.waiting(Self.debounce) == 1 })
                #expect(watched.sleeper.cancelled == 0)

                await watched.watcher.noteChange()
                #expect(
                    await eventually { watched.sleeper.cancelled == 1 && watched.sleeper.waiting(Self.debounce) == 1 })
                #expect(watched.calls.count == 0)
            }
        }

        @Test("an event from a source the watcher has replaced is dropped")
        func staleEventIsDropped() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                let first = await watched.watcher.generation
                await watched.watcher.noteChange()
                #expect(await watched.waitForCalls(1))
                let second = await watched.watcher.generation
                #expect(second != first)

                await watched.watcher.changed(from: first)
                await letTasksRun()
                #expect(watched.sleeper.waiting(Self.debounce) == 0)

                await watched.watcher.changed(from: second)
                #expect(await eventually { watched.debounceIsWaiting })
            }
        }

        // MARK: A folder that is not there

        @Test("a folder that is missing at start is looked for again until it appears, then watched")
        func folderCreatedAfterStart() async throws {
            try await withWatcher(createFolder: false) { watched in
                await watched.watcher.start()
                #expect(await watched.watcher.state == .waitingForFolder)
                #expect(await eventually { watched.sleeper.waiting(Self.retry) == 1 })

                // Still missing: it looks again after the interval, and reports nothing.
                watched.sleeper.fire(Self.retry)
                #expect(await eventually { watched.sleeper.waiting(Self.retry) == 1 })
                #expect(watched.calls.count == 0)
                #expect(await watched.watcher.state == .waitingForFolder)

                try FileManager.default.createDirectory(at: watched.folder.url, withIntermediateDirectories: true)
                watched.sleeper.fire(Self.retry)
                #expect(await eventually { watched.calls.count == 1 })
                #expect(await watched.watcher.state == .watching)
                #expect(watched.sleeper.waiting(Self.retry) == 0)

                try watched.folder.writeTheme("night", spacingMD: 14)
                #expect(await watched.waitForCalls(2))
            }
        }

        @Test("a folder that is removed and created again is watched again")
        func folderRemovedAndRecreated() async throws {
            try await withWatcher { watched in
                try watched.folder.writeTheme("night", spacingMD: 14)
                await watched.watcher.start()
                #expect(await watched.watcher.state == .watching)

                try FileManager.default.removeItem(at: watched.folder.url)
                #expect(await watched.waitForCalls(1))
                #expect(await watched.watcher.state == .waitingForFolder)
                #expect(await eventually { watched.sleeper.waiting(Self.retry) == 1 })

                try FileManager.default.createDirectory(at: watched.folder.url, withIntermediateDirectories: true)
                #expect(
                    await eventually {
                        watched.sleeper.fire(Self.retry)
                        return watched.calls.count == 2
                    })
                #expect(await watched.watcher.state == .watching)

                try watched.folder.writeTheme("night", spacingMD: 15)
                #expect(await watched.waitForCalls(3))
            }
        }

        @Test("stopping while it waits for the folder ends the wait")
        func stopWhileWaitingForTheFolder() async throws {
            try await withWatcher(createFolder: false) { watched in
                await watched.watcher.start()
                #expect(await eventually { watched.sleeper.waiting(Self.retry) == 1 })

                await watched.watcher.stop()
                #expect(watched.sleeper.waiting(Self.retry) == 0)
                try FileManager.default.createDirectory(at: watched.folder.url, withIntermediateDirectories: true)
                watched.sleeper.fire(Self.retry)
                await letTasksRun()
                #expect(watched.calls.count == 0)
                #expect(await watched.watcher.state == .stopped)
            }
        }

        @Test("starting twice does not watch twice")
        func startTwice() async throws {
            try await withWatcher { watched in
                await watched.watcher.start()
                let generation = await watched.watcher.generation
                await watched.watcher.start()
                #expect(await watched.watcher.generation == generation)
                try watched.folder.writeTheme("night", spacingMD: 14)
                #expect(await watched.waitForCalls(1))
            }
        }
    }
#endif
