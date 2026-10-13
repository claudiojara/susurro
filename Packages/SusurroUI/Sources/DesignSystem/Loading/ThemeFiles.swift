import Foundation

/// What counts as a theme file, and how one is read safely. The store lists theme files, the debug watcher watches them,
/// and the loader reads them, all by these rules.
///
/// A theme file is a `*.json` entry that is a regular file, or a symlink that leads to one. A pipe, a device, or a
/// folder named `x.json` is not a theme file and is never read, because reading it could wait forever or never end.
nonisolated enum ThemeFiles {
    /// A theme file is a few kilobytes. A file over this size is refused instead of read into memory.
    static let sizeLimit = 256 * 1024

    /// The theme files in `directory`, hidden files left out. A folder that is missing or cannot be listed has none.
    static func urls(in directory: URL) -> [URL] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return entries.filter(isThemeFile)
    }

    static func isThemeFile(_ url: URL) -> Bool {
        var info = stat()
        // `stat` follows a symlink, so a link counts as what it points to.
        return url.pathExtension.lowercased() == "json" && stat(url.path, &info) == 0
            && info.st_mode & S_IFMT == S_IFREG
    }

    /// The bytes of a theme file, if it is a regular file of at most `sizeLimit` bytes.
    ///
    /// The type and the size are read from the open file, not from its name, so a file that is swapped after a check
    /// cannot get past it. The read stops one byte over the limit, so a file that grows is caught too.
    static func contents(of url: URL) throws(ThemeError) -> Data {
        let name = url.lastPathComponent
        // Without O_NONBLOCK, opening a pipe waits for someone to write to it.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw .unreadable(file: name, reason: String(cString: strerror(errno))) }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw .unreadable(file: name, reason: "It is not a regular file.")
        }
        let tooBig = ThemeError.unreadable(file: name, reason: "It is larger than \(sizeLimit / 1024) KB.")
        guard info.st_size <= sizeLimit else { throw tooBig }
        let data: Data
        do {
            data =
                try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).read(upToCount: sizeLimit + 1)
                ?? Data()
        } catch {
            throw .unreadable(file: name, reason: error.localizedDescription)
        }
        guard data.count <= sizeLimit else { throw tooBig }
        return data
    }
}
