import Foundation
import Testing

/// `commit-references.sh` runs in the job that holds the write token. The archive it unpacks comes from the job that
/// ran the pull request's code, so it must take pictures and nothing else.
@Suite("Commit references script")
struct CommitReferencesTests {
    private static let snapshots = "Packages/SusurroUI/Tests/DesignSystemTests/Atoms/__Snapshots__"
    private static let picture = "\(snapshots)/AtomSnapshotTests/labels-scheme.light.png"
    private static let stamp = "\(snapshots)/environment.txt"

    private enum Entry {
        case file(String)
        /// A file stored under another name, as an archive made by hand can.
        case stored(as: String)
        case symlink(String)
    }

    private struct Checkout {
        let sandbox: ScriptSandbox
        let work: URL

        init(_ sandbox: ScriptSandbox) throws {
            self.sandbox = sandbox
            work = sandbox.folder.file("work")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try sandbox.git(["init", "--initial-branch=feat/x"], in: work)
            try Data("base".utf8).write(to: work.appendingPathComponent("README.md"))
            try sandbox.git(["add", "."], in: work)
            try sandbox.git(["commit", "-m", "base"], in: work)
        }

        var head: String { (try? sandbox.git(["rev-parse", "HEAD"], in: work)) ?? "" }

        func archive(_ entries: [Entry], named name: String = "references.tar") throws -> URL {
            let stage = sandbox.folder.file("stage-\(name)")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            var names: [String] = []
            for entry in entries {
                switch entry {
                case .file(let path):
                    let url = stage.appendingPathComponent(path)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data("contents of \(path)".utf8).write(to: url)
                    names.append(path)
                case .stored(let path):
                    try Data("contents of \(path)".utf8).write(to: stage.appendingPathComponent("payload"))
                case .symlink(let path):
                    let url = stage.appendingPathComponent(path)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/etc/hosts")
                    names.append(path)
                }
            }
            let archive = sandbox.folder.file(name)
            var arguments = ["-cf", archive.path]
            for entry in entries {
                if case .stored(let path) = entry {
                    arguments += ["-P", "-s", "|^payload$|\(path)|", "payload"]
                }
            }
            if !names.isEmpty {
                try Data(names.joined(separator: "\n").utf8).write(to: sandbox.folder.file("names-\(name).txt"))
                arguments += ["-T", sandbox.folder.file("names-\(name).txt").path]
            }
            try sandbox.tool("/usr/bin/tar", arguments, in: stage)
            return archive
        }

        func commit(_ archive: URL) throws -> ScriptSandbox.Result {
            try sandbox.run("commit-references.sh", arguments: [archive.path], in: work)
        }
    }

    @Test("the pictures and the environment record are unpacked and committed by the bot")
    func commitsThePictures() throws {
        let sandbox = try ScriptSandbox()
        let checkout = try Checkout(sandbox)
        let archive = try checkout.archive([.file(Self.picture), .file(Self.stamp)])
        let before = checkout.head

        let result = try checkout.commit(archive)

        #expect(result.status == 0, "\(result.output)")
        #expect(checkout.head != before)
        let log = try sandbox.git(["log", "-1", "--format=%an|%ae|%s"], in: checkout.work)
        #expect(
            log
                == "github-actions[bot]|41898282+github-actions[bot]@users.noreply.github.com|test(ui): record snapshot references"
        )
        let changed = try sandbox.git(["show", "--name-only", "--format=", "HEAD"], in: checkout.work)
        #expect(changed.split(separator: "\n").map(String.init).sorted() == [Self.picture, Self.stamp].sorted())
        #expect(sandbox.writtenOutputs == ["committed=true"])
    }

    @Test("references that are already in the branch make no commit")
    func commitsNothingWhenNothingChanged() throws {
        let sandbox = try ScriptSandbox()
        let checkout = try Checkout(sandbox)
        let archive = try checkout.archive([.file(Self.picture)])
        _ = try checkout.commit(archive)
        let committed = checkout.head
        try Data().write(to: sandbox.githubOutput)

        let result = try checkout.commit(archive)

        #expect(result.status == 0, "\(result.output)")
        #expect(checkout.head == committed)
        #expect(sandbox.writtenOutputs == ["committed=false"])
    }

    @Test("only the references are committed, not other files that are in the working tree")
    func commitsNothingButReferences() throws {
        let sandbox = try ScriptSandbox()
        let checkout = try Checkout(sandbox)
        let stray = checkout.work.appendingPathComponent("Packages/SusurroUI/Sources/Stray.swift")
        try FileManager.default.createDirectory(
            at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: stray)
        let archive = try checkout.archive([.file(Self.picture)])

        let result = try checkout.commit(archive)

        #expect(result.status == 0, "\(result.output)")
        let changed = try sandbox.git(["show", "--name-only", "--format=", "HEAD"], in: checkout.work)
        #expect(changed == Self.picture)
        #expect(
            try sandbox.git(["status", "--porcelain", "--untracked-files=all"], in: checkout.work)
                == "?? Packages/SusurroUI/Sources/Stray.swift")
    }

    private static let refused: [(name: String, entries: [Entry])] = [
        ("a workflow file", [.file(".github/workflows/ci.yml")]),
        ("a script next to the pictures", [.file("\(snapshots)/AtomSnapshotTests/run.sh")]),
        ("a picture outside a Tests folder", [.file("Packages/SusurroUI/Sources/DesignSystem/__Snapshots__/a.png")]),
        ("a picture outside Packages", [.file("Tools/Tests/__Snapshots__/a.png")]),
        ("a path that climbs out of the folder", [.stored(as: "Packages/../../outside.png")]),
        ("a picture path that climbs out of Tests", [.stored(as: "Packages/SusurroUI/Tests/../__Snapshots__/a.png")]),
        ("a link named like a picture", [.symlink(picture)]),
        ("a good picture with a bad one next to it", [.file(picture), .file(".github/workflows/ci.yml")]),
    ]

    @Test("an archive with anything but pictures is refused whole, and nothing is unpacked", arguments: refused.indices)
    func refusesAnythingElse(index: Int) throws {
        let (name, entries) = Self.refused[index]
        let sandbox = try ScriptSandbox()
        let checkout = try Checkout(sandbox)
        let archive = try checkout.archive(entries)
        let before = checkout.head

        let result = try checkout.commit(archive)

        #expect(result.status != 0, "\(name) was accepted")
        #expect(result.output.lowercased().contains("unexpected"), "\(name): \(result.output)")
        #expect(checkout.head == before)
        let status = try sandbox.git(["status", "--porcelain", "--untracked-files=all"], in: checkout.work)
        #expect(status == "", "\(name) left files behind: \(status)")
        #expect(sandbox.writtenOutputs.isEmpty)
    }
}
