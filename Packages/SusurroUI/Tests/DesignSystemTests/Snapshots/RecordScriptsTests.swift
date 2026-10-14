import Foundation
import Testing

/// The scripts of the `record-snapshots` workflow, run for real against a stand-in `gh` and local git repositories.
/// They hold the decisions that must not depend on a person reading a log: where recording may happen, what may be
/// committed, and when CI has to be started.
@Suite("Record snapshots scripts")
struct RecordScriptsTests {
    private let sha = String(repeating: "a1", count: 20)

    private func pullRequests(branch: String, repository: String, sha: String) -> String {
        """
        [{"head": {"ref": "\(branch)", "sha": "\(sha)", "repo": {"full_name": "\(repository)"}}}]
        """
    }

    // MARK: guard-record-target.sh

    private func guardTarget(
        _ sandbox: ScriptSandbox, branch: String, pulls: String = "[]", defaultBranch: String = "main"
    ) throws -> ScriptSandbox.Result {
        try sandbox.run(
            "guard-record-target.sh",
            environment: [
                "REPO": "claudiojara/susurro", "BRANCH": branch, "DEFAULT_BRANCH": defaultBranch, "STUB_PULLS": pulls,
            ])
    }

    @Test("the default branch is refused before anything is asked of GitHub")
    func refusesTheDefaultBranch() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "main", pulls: pullRequests(branch: "main", repository: "claudiojara/susurro", sha: sha))
        #expect(result.status != 0)
        #expect(result.output.contains("default branch"), "\(result.output)")
        #expect(sandbox.ghCalls.isEmpty)
        #expect(sandbox.writtenOutputs.isEmpty)
    }

    @Test("another default branch name is refused too")
    func refusesTheDefaultBranchWhateverItIsCalled() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "trunk", pulls: pullRequests(branch: "trunk", repository: "claudiojara/susurro", sha: sha),
            defaultBranch: "trunk")
        #expect(result.status != 0)
        #expect(result.output.contains("default branch"), "\(result.output)")
    }

    @Test("a branch with no open pull request is refused")
    func refusesABranchWithoutAPullRequest() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(sandbox, branch: "feat/x", pulls: "[]")
        #expect(result.status != 0)
        #expect(result.output.contains("open pull request"), "\(result.output)")
        #expect(sandbox.writtenOutputs.isEmpty)
    }

    @Test("a pull request from a fork is refused, because the job would push to a branch it does not own")
    func refusesAPullRequestFromAFork() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "feat/x", pulls: pullRequests(branch: "feat/x", repository: "someone/susurro", sha: sha))
        #expect(result.status != 0)
        #expect(result.output.contains("open pull request"), "\(result.output)")
        #expect(sandbox.writtenOutputs.isEmpty)
    }

    @Test("a pull request from another branch of the repository is not the branch asked for")
    func refusesAPullRequestOfAnotherBranch() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "feat/x",
            pulls: pullRequests(branch: "feat/other", repository: "claudiojara/susurro", sha: sha))
        #expect(result.status != 0)
        #expect(sandbox.writtenOutputs.isEmpty)
    }

    @Test("an answer that is not a commit id is refused")
    func refusesAMalformedCommitId() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "feat/x",
            pulls: pullRequests(branch: "feat/x", repository: "claudiojara/susurro", sha: "not-a-sha"))
        #expect(result.status != 0)
        #expect(sandbox.writtenOutputs.isEmpty)
    }

    @Test("an open pull request of this repository gives the branch and the commit to record on")
    func acceptsAPullRequestOfTheRepository() throws {
        let sandbox = try ScriptSandbox()
        let result = try guardTarget(
            sandbox, branch: "feat/x",
            pulls: pullRequests(branch: "feat/x", repository: "claudiojara/susurro", sha: sha))
        #expect(result.status == 0, "\(result.output)")
        #expect(sandbox.writtenOutputs == ["branch=feat/x", "sha=\(sha)"])
        let call = try #require(sandbox.ghCalls.first)
        #expect(call.contains("repos/claudiojara/susurro/pulls"), "\(call)")
        #expect(call.contains("head=claudiojara:feat/x"), "\(call)")
    }

    // MARK: dispatch-ci.sh

    private func dispatch(_ sandbox: ScriptSandbox, runs: String) throws -> ScriptSandbox.Result {
        try sandbox.run(
            "dispatch-ci.sh",
            environment: ["REPO": "claudiojara/susurro", "BRANCH": "feat/x", "SHA": sha, "STUB_RUNS": runs])
    }

    private static let started = "workflow run ci.yml --repo claudiojara/susurro --ref feat/x"

    @Test("CI is started for a head that has no run at all")
    func startsCIWhenThereIsNoRun() throws {
        let sandbox = try ScriptSandbox()
        let result = try dispatch(sandbox, runs: "[]")
        #expect(result.status == 0, "\(result.output)")
        #expect(sandbox.ghCalls.contains(Self.started), "\(sandbox.ghCalls)")
        #expect(sandbox.ghCalls.contains { $0.hasPrefix("run list") && $0.contains("--commit \(sha)") })
    }

    @Test(
        "CI is started when the only runs of the head are ones that gave no result",
        arguments: [
            #"[{"status":"completed","conclusion":"action_required"}]"#,
            #"[{"status":"completed","conclusion":"skipped"}]"#,
            #"[{"status":"completed","conclusion":"cancelled"},{"status":"completed","conclusion":"action_required"}]"#,
        ])
    func startsCIWhenNoRunGaveAResult(runs: String) throws {
        let sandbox = try ScriptSandbox()
        let result = try dispatch(sandbox, runs: runs)
        #expect(result.status == 0, "\(result.output)")
        #expect(sandbox.ghCalls.contains(Self.started), "\(sandbox.ghCalls)")
    }

    @Test(
        "CI is not started again when a run of the head passed, failed, or is still going",
        arguments: [
            #"[{"status":"completed","conclusion":"success"}]"#,
            #"[{"status":"completed","conclusion":"failure"}]"#,
            #"[{"status":"in_progress","conclusion":""}]"#,
            #"[{"status":"queued","conclusion":""},{"status":"completed","conclusion":"action_required"}]"#,
        ])
    func leavesAHeadThatHasARunAlone(runs: String) throws {
        let sandbox = try ScriptSandbox()
        let result = try dispatch(sandbox, runs: runs)
        #expect(result.status == 0, "\(result.output)")
        #expect(!sandbox.ghCalls.contains { $0.hasPrefix("workflow run") }, "\(sandbox.ghCalls)")
    }

    // MARK: publish-references.sh

    /// A bare repository standing in for GitHub, a clone of it on `feat/x` at `base`, and the commit the record job
    /// made on top of it.
    private struct Remote {
        let sandbox: ScriptSandbox
        let bare: URL
        let work: URL
        let base: String

        init(_ sandbox: ScriptSandbox) throws {
            self.sandbox = sandbox
            bare = sandbox.folder.file("remote.git")
            work = sandbox.folder.file("work")
            let seed = sandbox.folder.file("seed")
            try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
            try sandbox.git(["init", "--bare", "--initial-branch=main"], in: bare)
            try sandbox.git(["init", "--initial-branch=feat/x"], in: seed)
            try Data("one".utf8).write(to: seed.appendingPathComponent("a.txt"))
            try sandbox.git(["add", "."], in: seed)
            try sandbox.git(["commit", "-m", "base"], in: seed)
            try sandbox.git(["push", bare.path, "feat/x"], in: seed)
            base = try sandbox.git(["rev-parse", "HEAD"], in: seed)
            try sandbox.git(["clone", "--branch", "feat/x", bare.path, work.path], in: sandbox.folder.url)
        }

        func commitReferences() throws {
            try Data("two".utf8).write(to: work.appendingPathComponent("b.txt"))
            try sandbox.git(["add", "."], in: work)
            try sandbox.git(["commit", "-m", "test(ui): record snapshot references"], in: work)
        }

        func remoteHead() throws -> String {
            try sandbox.git(["rev-parse", "refs/heads/feat/x"], in: bare)
        }

        func publish(runs: String = "[]") throws -> ScriptSandbox.Result {
            try sandbox.run(
                "publish-references.sh",
                environment: [
                    "REPO": "claudiojara/susurro", "BRANCH": "feat/x", "SHA": base, "GH_TOKEN": "secret-token-value",
                    "REMOTE_URL": bare.path, "STUB_RUNS": runs,
                ], in: work)
        }
    }

    @Test("the new commit is pushed to the branch and CI is started for it")
    func pushesAndStartsCI() throws {
        let sandbox = try ScriptSandbox()
        let remote = try Remote(sandbox)
        try remote.commitReferences()
        let committed = try sandbox.git(["rev-parse", "HEAD"], in: remote.work)

        let result = try remote.publish()

        #expect(result.status == 0, "\(result.output)")
        #expect(try remote.remoteHead() == committed)
        #expect(sandbox.ghCalls.contains(Self.started), "\(sandbox.ghCalls)")
        #expect(!result.output.contains("secret-token-value"))
    }

    @Test("with nothing to push, a head that has no CI result still gets CI, so a run after a failed dispatch recovers")
    func startsCIWhenThereWasNothingToPush() throws {
        let sandbox = try ScriptSandbox()
        let remote = try Remote(sandbox)

        let result = try remote.publish(runs: #"[{"status":"completed","conclusion":"action_required"}]"#)

        #expect(result.status == 0, "\(result.output)")
        #expect(try remote.remoteHead() == remote.base)
        #expect(result.output.contains("Nothing to push"), "\(result.output)")
        #expect(sandbox.ghCalls.contains(Self.started), "\(sandbox.ghCalls)")
    }

    @Test("with nothing to push and a head that has a CI result, nothing is started")
    func leavesAHeadWithResultsAlone() throws {
        let sandbox = try ScriptSandbox()
        let remote = try Remote(sandbox)

        let result = try remote.publish(runs: #"[{"status":"completed","conclusion":"success"}]"#)

        #expect(result.status == 0, "\(result.output)")
        #expect(!sandbox.ghCalls.contains { $0.hasPrefix("workflow run") })
    }

    @Test("a branch that moved while the references were recorded is not overwritten, and CI is not started")
    func refusesABranchThatMoved() throws {
        let sandbox = try ScriptSandbox()
        let remote = try Remote(sandbox)
        try remote.commitReferences()
        // Someone else pushes to the branch in the meantime.
        let other = sandbox.folder.file("other")
        try sandbox.git(["clone", "--branch", "feat/x", remote.bare.path, other.path], in: sandbox.folder.url)
        try Data("three".utf8).write(to: other.appendingPathComponent("c.txt"))
        try sandbox.git(["add", "."], in: other)
        try sandbox.git(["commit", "-m", "another change"], in: other)
        try sandbox.git(["push", "origin", "feat/x"], in: other)
        let moved = try remote.remoteHead()

        let result = try remote.publish()

        #expect(result.status != 0)
        #expect(result.output.contains("moved"), "\(result.output)")
        #expect(try remote.remoteHead() == moved)
        #expect(!sandbox.ghCalls.contains { $0.hasPrefix("workflow run") })
    }
}
