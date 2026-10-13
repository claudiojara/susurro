#if DEBUG
    import Foundation

    /// Calls `onChange` shortly after a theme file in a folder is added, edited, replaced, or removed, so that a theme
    /// can be edited while the app runs. Only debug builds have it. The folder must exist when `start()` runs.
    ///
    /// It watches the folder, which sees files come and go and be replaced, and each `.json` file in it, which sees an
    /// edit in place. The files are watched again after every change, because a replaced file is a new file. A save
    /// often shows up as several events, such as emptying the file and then writing it, so `onChange` is called once,
    /// `debounce` after the last of them.
    public actor ThemeFileWatcher {
        private let directory: URL
        private let debounce: Duration
        private let onChange: @Sendable () async -> Void
        private var sources: [any DispatchSourceFileSystemObject] = []
        private var pending: Task<Void, Never>?
        private var running = false

        public init(
            directory: URL, debounce: Duration = .milliseconds(150), onChange: @escaping @Sendable () async -> Void
        ) {
            self.directory = directory
            self.debounce = debounce
            self.onChange = onChange
        }

        public func start() {
            running = true
            watch()
        }

        public func stop() {
            running = false
            pending?.cancel()
            pending = nil
            for source in sources { source.cancel() }
            sources = []
        }

        private func watch() {
            for source in sources { source.cancel() }
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            let urls = [directory] + files.filter { $0.pathExtension.lowercased() == "json" }
            sources = urls.compactMap(source)
        }

        private func source(for url: URL) -> (any DispatchSourceFileSystemObject)? {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in
                Task { await self?.changed() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }

        /// An event already on its way when `stop()` ran is dropped here, so a stopped watcher stays stopped.
        private func changed() {
            guard running else { return }
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled, running else { return }
                watch()
                await onChange()
            }
        }
    }
#endif
