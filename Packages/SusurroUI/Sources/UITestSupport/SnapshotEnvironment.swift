import Foundation

/// The machine a set of snapshot references was made on. Text is drawn a little differently by each macOS, and a runner
/// image that moves to a new macOS or Xcode moves every picture by a few pixels, with nothing in the diff to say why.
/// So the recording writes this next to the references (`environment.txt` in `__Snapshots__`), and a run on CI that finds
/// another environment fails with that reason instead of a list of pictures that look the same.
public nonisolated struct SnapshotEnvironment: Equatable, Sendable {
    /// Version and build, such as `27.0.1 (25A5349a)`.
    public let macOS: String
    /// Version and build, such as `Xcode 27.0 (27A266a)`.
    public let xcode: String

    public init(macOS: String, xcode: String) {
        self.macOS = macOS
        self.xcode = xcode
    }

    /// Reads what `text` wrote. Nil when a line is missing or empty.
    public init?(parsing text: String) {
        var macOS: String?
        var xcode: String?
        for line in text.split(separator: "\n") {
            if line.hasPrefix(Self.macOSKey) {
                macOS = String(line.dropFirst(Self.macOSKey.count))
            } else if line.hasPrefix(Self.xcodeKey) {
                xcode = String(line.dropFirst(Self.xcodeKey.count))
            }
        }
        guard let macOS, let xcode, !macOS.isEmpty, !xcode.isEmpty else { return nil }
        self.init(macOS: macOS, xcode: xcode)
    }

    private static let macOSKey = "macOS: "
    private static let xcodeKey = "Xcode: "

    public var text: String { "\(Self.macOSKey)\(macOS)\n\(Self.xcodeKey)\(xcode)\n" }

    // MARK: This machine

    /// The machine running the tests, found once.
    public static func current() -> SnapshotEnvironment { measured }

    private static let measured = SnapshotEnvironment(macOS: macOSVersion(), xcode: xcodeVersion())

    private static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = Self.versionNumber(
            major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
        return "\(number) (\(kernelOSVersion()))"
    }

    /// `27.0.1`, and `27.1` when there is no patch, the way macOS names its releases.
    static func versionNumber(major: Int, minor: Int, patch: Int) -> String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    /// The build, such as `25A5349a`, which `sw_vers -buildVersion` prints.
    private static func kernelOSVersion() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown build" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return "unknown build" }
        return String(cString: bytes)
    }

    /// `xcodebuild -version` prints `Xcode 27.0` and `Build version 27A266a`.
    private static func xcodeVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "Xcode unknown" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard let name = lines.first(where: { $0.hasPrefix("Xcode ") }) else { return "Xcode unknown" }
        let build = lines.first { $0.hasPrefix("Build version ") }.map { String($0.dropFirst("Build version ".count)) }
        return build.map { "\(name) (\($0))" } ?? name
    }

    // MARK: Comparing

    /// Why a run on `current` cannot be trusted against references recorded on `recorded`, or nil when it can.
    public static func problem(recorded: SnapshotEnvironment?, current: SnapshotEnvironment) -> String? {
        guard let recorded else {
            return """
                The references have no record of the machine that made them (environment.txt is missing from \
                __Snapshots__), so there is no telling whether this run matches. Record them on the CI image: put the \
                label `record-snapshots` on the pull request, or run `gh workflow run record-snapshots.yml --ref <branch>`.
                """
        }
        guard recorded != current else { return nil }
        return """
            The runner image changed. The references were recorded on macOS \(recorded.macOS) with \(recorded.xcode); \
            this run is on macOS \(current.macOS) with \(current.xcode). Text is drawn a little differently by each \
            version, so a picture that fails here may not come from the code. Re-record the references on this image \
            (the label `record-snapshots` on the pull request) and read the new pictures.
            """
    }

    /// Whether a mismatch has to fail the run: on CI, where the references were made, it does; on a developer's Mac,
    /// which is expected to differ, it is a note.
    public static func mustMatch(_ environment: [String: String]) -> Bool {
        environment["CI"] == "true"
    }

    // MARK: The record on disk

    /// Where the record of the references of `testFile` is: in the `__Snapshots__` folder next to the file.
    public static func recordURL(forTestFile testFile: String) -> URL {
        URL(fileURLWithPath: testFile).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
            .appendingPathComponent("environment.txt")
    }

    public static func read(from url: URL) -> SnapshotEnvironment? {
        (try? String(contentsOf: url, encoding: .utf8)).flatMap(SnapshotEnvironment.init(parsing:))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
