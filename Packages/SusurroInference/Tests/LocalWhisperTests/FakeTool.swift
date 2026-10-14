import Foundation

/// A folder for one test, with the fake command line tools it writes in it. A tool is a small script made when the test
/// runs, so that its permissions are what the test says. The folder is removed with the value.
final class ToolFolder: @unchecked Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("susurro-tools-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// A script with this body, which can be run unless `executable` is false. Returns its path.
    @discardableResult
    func script(_ name: String, _ body: String, executable: Bool = true) -> String {
        let file = url.appendingPathComponent(name)
        try? Data("#!/bin/sh\n\(body)\n".utf8).write(to: file)
        try? FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        return file.path
    }

    func path(_ name: String) -> String { url.appendingPathComponent(name).path }

    var contents: [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [] }
}

/// Whether a process is still alive.
func isAlive(pid: Int32) -> Bool {
    kill(pid, 0) == 0
}

/// Waits up to two seconds for a condition that another thread makes true.
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
