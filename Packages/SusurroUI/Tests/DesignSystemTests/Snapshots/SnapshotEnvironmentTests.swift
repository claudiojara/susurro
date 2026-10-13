import AppKit
import Foundation
import SwiftUI
import Testing

@testable import UITestSupport

@Suite("Snapshot environment")
struct SnapshotEnvironmentTests {
    private let recorded = SnapshotEnvironment(macOS: "27.0.1 (25A5349a)", xcode: "Xcode 27.0 (27A266a)")

    @Test("the record is two lines of text and reads back as the same environment")
    func textRoundTrips() {
        #expect(recorded.text == "macOS: 27.0.1 (25A5349a)\nXcode: Xcode 27.0 (27A266a)\n")
        #expect(SnapshotEnvironment(parsing: recorded.text) == recorded)
        let other = SnapshotEnvironment(macOS: "26.6.2 (25G83)", xcode: "Xcode 27.0 (27A266a)")
        #expect(SnapshotEnvironment(parsing: other.text) == other)
        #expect(other != recorded)
    }

    @Test(
        "a record that lacks a line, or is not a record, is not read",
        arguments: [
            "", "macOS: 27.0.1 (25A5349a)\n", "Xcode: Xcode 27.0\n", "nothing to see\n", "macOS:\nXcode:\n",
        ])
    func rejectsWhatIsNotARecord(text: String) {
        #expect(SnapshotEnvironment(parsing: text) == nil)
    }

    @Test("the same environment is no problem")
    func sameEnvironmentIsNoProblem() {
        #expect(SnapshotEnvironment.problem(recorded: recorded, current: recorded) == nil)
    }

    @Test("a new macOS is a problem that names both versions and says to record again")
    func newMacOSIsAProblem() throws {
        let current = SnapshotEnvironment(macOS: "27.1 (25B100)", xcode: recorded.xcode)
        let message = try #require(SnapshotEnvironment.problem(recorded: recorded, current: current))
        #expect(message.contains("runner image changed"))
        #expect(message.contains("27.0.1 (25A5349a)"))
        #expect(message.contains("27.1 (25B100)"))
        #expect(message.contains("record-snapshots"))
    }

    @Test("a new Xcode is a problem too")
    func newXcodeIsAProblem() throws {
        let current = SnapshotEnvironment(macOS: recorded.macOS, xcode: "Xcode 27.1 (27B1)")
        let message = try #require(SnapshotEnvironment.problem(recorded: recorded, current: current))
        #expect(message.contains("Xcode 27.0 (27A266a)"))
        #expect(message.contains("Xcode 27.1 (27B1)"))
    }

    @Test("references with no record are a problem, since nobody can say what made them")
    func missingRecordIsAProblem() throws {
        let message = try #require(SnapshotEnvironment.problem(recorded: nil, current: recorded))
        #expect(message.contains("no record"))
        #expect(message.contains("record-snapshots"))
    }

    @Test(
        "only a run on CI has to match",
        arguments: [
            (["CI": "true"], true), (["CI": "false"], false), ([:], false), (["CI": "1"], false),
        ] as [([String: String], Bool)])
    func onlyCIHasToMatch(environment: [String: String], required: Bool) {
        #expect(SnapshotEnvironment.mustMatch(environment) == required)
    }

    @Test("the running machine is described by its macOS version and build and by its Xcode")
    func currentDescribesTheMachine() {
        let current = SnapshotEnvironment.current()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(current.macOS.hasPrefix("\(version.majorVersion).\(version.minorVersion)"), "\(current.macOS)")
        #expect(current.macOS.contains("(") && current.macOS.hasSuffix(")"), "\(current.macOS)")
        #expect(current.xcode.hasPrefix("Xcode "), "\(current.xcode)")
        #expect(current.xcode.contains("("), "\(current.xcode)")
    }

    @Test(
        "a macOS version leaves out a patch of zero, as macOS does",
        arguments: [
            (27, 0, 1, "27.0.1"), (27, 1, 0, "27.1"), (26, 6, 2, "26.6.2"), (15, 0, 0, "15.0"),
        ] as [(Int, Int, Int, String)])
    func versionNumbers(major: Int, minor: Int, patch: Int, expected: String) {
        #expect(SnapshotEnvironment.versionNumber(major: major, minor: minor, patch: patch) == expected)
    }

    @Test("the record sits in the __Snapshots__ folder of the test file")
    func recordSitsNextToTheReferences() {
        let url = SnapshotEnvironment.recordURL(
            forTestFile: "/repo/Tests/DesignSystemTests/Atoms/AtomSnapshotTests.swift")
        #expect(url.path == "/repo/Tests/DesignSystemTests/Atoms/__Snapshots__/environment.txt")
    }

    @Test("a record written to a file is read back, and a missing file reads as no record")
    func recordIsWrittenAndRead() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        let url = folder.file("Atoms/__Snapshots__/environment.txt")
        #expect(SnapshotEnvironment.read(from: url) == nil)
        try recorded.write(to: url)
        #expect(SnapshotEnvironment.read(from: url) == recorded)
        let newer = SnapshotEnvironment(macOS: "27.1 (25B100)", xcode: recorded.xcode)
        try newer.write(to: url)
        #expect(SnapshotEnvironment.read(from: url) == newer)
    }
}

/// How `assertViewSnapshot` uses the record: it writes it while recording and compares with it otherwise.
@MainActor
@Suite("Snapshot environment check")
struct SnapshotEnvironmentCheckTests {
    private let other = SnapshotEnvironment(macOS: "1.0 (1A1)", xcode: "Xcode 1.0 (1A1)")

    private func check(_ folder: ScratchFolder, environment: [String: String]) -> [String] {
        var reports: [String] = []
        SnapshotSupport.checkEnvironment(
            testFile: folder.file("Atoms/AtomSnapshotTests.swift").path, environment: environment
        ) { reports.append($0) }
        return reports
    }

    private func recordURL(_ folder: ScratchFolder) -> URL {
        folder.file("Atoms/__Snapshots__/environment.txt")
    }

    @Test("recording writes the environment of this machine and reports nothing")
    func recordingWritesTheRecord() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        let reports = check(folder, environment: ["SNAPSHOT_TESTING_RECORD": "all", "CI": "true"])
        #expect(reports.isEmpty)
        #expect(SnapshotEnvironment.read(from: recordURL(folder)) == SnapshotEnvironment.current())
    }

    @Test("on CI, a record of another environment fails the run with the reason")
    func ciFailsOnAnotherEnvironment() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        try other.write(to: recordURL(folder))
        let reports = check(folder, environment: ["CI": "true", "SNAPSHOT_TESTING_RECORD": "never"])
        #expect(reports.count == 1)
        #expect(reports.first?.contains("runner image changed") == true)
    }

    @Test("on CI, references with no record fail the run")
    func ciFailsWithoutARecord() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        let reports = check(folder, environment: ["CI": "true"])
        #expect(reports.count == 1)
        #expect(reports.first?.contains("no record") == true)
    }

    @Test("on CI, a record of this environment reports nothing")
    func ciPassesOnTheSameEnvironment() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        try SnapshotEnvironment.current().write(to: recordURL(folder))
        #expect(check(folder, environment: ["CI": "true"]).isEmpty)
    }

    @Test("on a developer's Mac, another environment is a note and not a failure")
    func otherMachinesOnlyGetANote() throws {
        let folder = try ScratchFolder()
        defer { folder.delete() }
        try other.write(to: recordURL(folder))
        #expect(check(folder, environment: [:]).isEmpty)
    }
}
