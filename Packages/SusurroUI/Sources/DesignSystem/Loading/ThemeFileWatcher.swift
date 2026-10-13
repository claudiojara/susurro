#if DEBUG
    import Foundation
    import os

    /// Calls `onChange` shortly after a theme file in a folder is added, edited, replaced, or removed, so that a theme
    /// can be edited while the app runs. Only debug builds have it.
    ///
    /// It watches the folder, which sees files come and go and be replaced, and each theme file in it, which sees an
    /// edit in place. The files are watched again after every change, because a replaced file is a new file. A save
    /// often shows up as several events, such as emptying the file and then writing it, so `onChange` is called once,
    /// `debounce` after the last of them.
    ///
    /// The folder does not have to exist. A folder that is missing when `start()` runs, or that is removed later, is
    /// looked for again every `retryInterval` until it is there, and `onChange` is called when it is found, so
    /// whoever listens reads what it holds. `state` says which of the two the watcher is in.
    public actor ThemeFileWatcher {
        public enum State: Sendable, Equatable {
            case stopped
            /// The folder is missing and the watcher is looking for it.
            case waitingForFolder
            case watching
        }

        private nonisolated static let logger = Logger(
            subsystem: "dev.claudiojara.susurro", category: "ThemeFileWatcher")

        private let directory: URL
        private let debounce: Duration
        private let retryInterval: Duration
        private let sleep: @Sendable (Duration) async throws -> Void
        private let onChange: @Sendable () async -> Void
        private var sources: [any DispatchSourceFileSystemObject] = []
        private var pending: Task<Void, Never>?
        private var retrying: Task<Void, Never>?
        private var running: Bool { state != .stopped }

        public private(set) var state = State.stopped
        /// Counts the times the sources were opened. An event carries the number of the sources it came from, and one
        /// from sources that were replaced since is dropped.
        private(set) var generation = 0

        /// `sleep` is how the watcher waits, for the debounce and for the retry; a test passes its own.
        public init(
            directory: URL, debounce: Duration = .milliseconds(150), retryInterval: Duration = .seconds(2),
            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
            onChange: @escaping @Sendable () async -> Void
        ) {
            self.directory = directory
            self.debounce = debounce
            self.retryInterval = retryInterval
            self.sleep = sleep
            self.onChange = onChange
        }

        /// Does nothing if it is already running.
        public func start() {
            guard !running else { return }
            state = .watching
            if !watch() { retryUntilFolderExists() }
        }

        public func stop() {
            state = .stopped
            pending?.cancel()
            pending = nil
            retrying?.cancel()
            retrying = nil
            generation += 1
            cancelSources()
        }

        // MARK: Watching

        /// Opens the sources again: the folder, and each theme file in it. False if the folder cannot be opened.
        private func watch() -> Bool {
            cancelSources()
            generation += 1
            guard let folder = source(for: directory, logFailure: state != .waitingForFolder) else {
                state = .waitingForFolder
                return false
            }
            state = .watching
            sources = [folder] + ThemeFiles.urls(in: directory).compactMap { source(for: $0, logFailure: true) }
            return true
        }

        private func cancelSources() {
            for source in sources { source.cancel() }
            sources = []
        }

        private func source(for url: URL, logFailure: Bool) -> (any DispatchSourceFileSystemObject)? {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                if logFailure {
                    let reason = String(cString: strerror(errno))
                    Self.logger.error(
                        "Cannot watch \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
                }
                return nil
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: .global(qos: .utility))
            source.setEventHandler { [weak self, generation] in
                Task { await self?.changed(from: generation) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }

        // MARK: Reacting

        /// An event from sources that were replaced, or that was already on its way when `stop()` ran, is dropped here.
        func changed(from generation: Int) {
            guard running, generation == self.generation else { return }
            noteChange()
        }

        /// Starts the wait again, so `onChange` is called `debounce` after the last event. Events call it through
        /// `changed(from:)`; a test calls it to stand in for one.
        func noteChange() {
            pending?.cancel()
            pending = Task {
                do { try await sleep(debounce) } catch { return }
                guard !Task.isCancelled, running else { return }
                if !watch() { retryUntilFolderExists() }
                await onChange()
            }
        }

        /// Looks for the folder every `retryInterval`, and when it is there watches it and calls `onChange`.
        private func retryUntilFolderExists() {
            guard retrying == nil else { return }
            retrying = Task {
                repeat {
                    do { try await sleep(retryInterval) } catch { return }
                    guard !Task.isCancelled, running else { return }
                } while !watch()
                retrying = nil
                await onChange()
            }
        }
    }
#endif
