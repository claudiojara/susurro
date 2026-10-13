import Foundation
import Testing

@testable import DesignSystem

@Suite("Theme files")
struct ThemeFilesTests {
    private let notRegular = "It is not a regular file."
    private let tooBig = "It is larger than 256 KB."

    private func withFolder(_ body: (ScratchFolder) throws -> Void) throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        try body(folder)
    }

    @Test("a symlink to a regular file loads like the file")
    func symlinkToAFile() throws {
        try withFolder { folder in
            try folder.write("real.json", #"{"schemaVersion": 1, "spacing": {"md": 14}}"#)
            try folder.makeSymlink("alias.json", to: folder.file("real.json"))
            let result = ThemeLoader.load(contentsOf: folder.file("alias.json"))
            #expect(result.errors == [])
            #expect(result.theme.spacing["md"] == 14)
        }
    }

    @Test(
        "an entry that is not a regular file is refused without being read",
        .timeLimit(.minutes(1)))
    func notRegularFiles() throws {
        try withFolder { folder in
            try folder.makeFIFO("pipe.json")
            try folder.makeFolder("folder.json")
            try folder.makeSymlink("alias-of-pipe.json", to: folder.file("pipe.json"))
            try folder.makeSymlink("alias-of-folder.json", to: folder.file("folder.json"))
            try folder.makeSymlink("dangling.json", to: folder.file("missing.json"))
            for name in ["pipe.json", "folder.json", "alias-of-pipe.json", "alias-of-folder.json"] {
                let result = ThemeLoader.load(contentsOf: folder.file(name))
                #expect(result.theme == .default, "\(name)")
                #expect(result.errors == [.unreadable(file: name, reason: notRegular)], "\(name)")
            }
            let dangling = ThemeLoader.load(contentsOf: folder.file("dangling.json"))
            #expect(dangling.errors.count == 1)
            if case .unreadable(let file, _) = dangling.errors.first {
                #expect(file == "dangling.json")
            } else {
                Issue.record("expected unreadable, got \(dangling.errors)")
            }
        }
    }

    @Test("a file over the size cap is refused with a message that says so, and one at the cap loads")
    func sizeCap() throws {
        try withFolder { folder in
            try folder.write("big.json", themeText(ofSize: ThemeFiles.sizeLimit + 1))
            let big = ThemeLoader.load(contentsOf: folder.file("big.json"))
            #expect(big.theme == .default)
            #expect(big.errors == [.unreadable(file: "big.json", reason: tooBig)])

            try folder.write("edge.json", themeText(ofSize: ThemeFiles.sizeLimit))
            let edge = ThemeLoader.load(contentsOf: folder.file("edge.json"))
            #expect(edge.errors == [])
        }
    }

    @Test("the cap is about 256 KB")
    func capValue() {
        #expect(ThemeFiles.sizeLimit == 256 * 1024)
    }

    @Test("a folder lists only the JSON files that are regular files, or links to one")
    func listing() throws {
        try withFolder { folder in
            try folder.write("night.json", themeText(ofSize: 40))
            try folder.write("Dawn.JSON", themeText(ofSize: 40))
            try folder.write("notes.txt", "not a theme")
            try folder.write(".hidden.json", themeText(ofSize: 40))
            try folder.makeFIFO("pipe.json")
            try folder.makeFolder("folder.json")
            try folder.makeSymlink("alias.json", to: folder.file("night.json"))
            try folder.makeSymlink("alias-of-pipe.json", to: folder.file("pipe.json"))
            try folder.makeSymlink("dangling.json", to: folder.file("missing.json"))
            let names = ThemeFiles.urls(in: folder.url).map(\.lastPathComponent).sorted()
            #expect(names == ["Dawn.JSON", "alias.json", "night.json"])
        }
    }

    @Test("a folder that is missing has no theme files")
    func missingFolder() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        #expect(ThemeFiles.urls(in: url) == [])
    }
}
