import Foundation
import Testing

/// What the workflows that run snapshots must keep true. The record job runs the code of a pull request, so it must
/// never hold a token that can write; the job that writes must never run that code. These tests read the workflow files
/// so that an edit that breaks either rule fails here, not in a review.
@Suite("Workflow policy")
struct WorkflowPolicyTests {
    private static let ci = ".github/workflows/ci.yml"
    private static let record = ".github/workflows/record-snapshots.yml"
    private static let workflows = [ci, record, ".github/workflows/codeql.yml"]

    private func workflow(_ path: String) throws -> WorkflowFile {
        let file = try WorkflowFile(path)
        #expect(!file.jobs.isEmpty, "\(path) has no jobs: the policy tests read none of it.")
        return file
    }

    private func recordWorkflow() throws -> WorkflowFile { try workflow(Self.record) }

    private func job(_ id: String) throws -> WorkflowFile.Job {
        try #require(try recordWorkflow().job(id), "record-snapshots.yml has no job \(id)")
    }

    // MARK: Every workflow

    @Test("every action is pinned to a commit, not to a tag that can move", arguments: workflows)
    func actionsArePinned(path: String) throws {
        let file = try workflow(path)
        let uses = file.jobs.flatMap(\.steps).compactMap(\.uses)
        #expect(!uses.isEmpty)
        for action in uses {
            #expect(action.wholeMatch(of: /[\w.\/-]+@[0-9a-f]{40}(\s+#.*)?/) != nil, "\(path): \(action) is not pinned")
        }
    }

    @Test("no script holds an expression, so a branch name or a title cannot become a command", arguments: workflows)
    func scriptsHoldNoExpressions(path: String) throws {
        let file = try workflow(path)
        for step in file.jobs.flatMap(\.steps) {
            #expect(!step.script.contains("${{"), "\(path): step \(step.name ?? "?") puts an expression in a script")
        }
    }

    @Test("every checkout drops the credentials it would leave in .git", arguments: workflows)
    func checkoutsDropCredentials(path: String) throws {
        let file = try workflow(path)
        let checkouts = file.jobs.flatMap(\.steps).filter { $0.uses?.hasPrefix("actions/checkout@") == true }
        #expect(!checkouts.isEmpty)
        for step in checkouts {
            #expect(step.text.contains("persist-credentials: false"), "\(path): a checkout keeps its credentials")
        }
    }

    // MARK: Recording

    @Test("nothing is allowed by default, and only the commit job may write")
    func onlyTheCommitJobWrites() throws {
        let file = try recordWorkflow()
        #expect(file.header.contains("permissions: {}"))
        let writers = file.jobs.filter { $0.text.contains(": write") }.map(\.id)
        #expect(writers == ["commit"])
        let commit = try job("commit")
        #expect(commit.text.contains("contents: write"))
        #expect(commit.text.contains("actions: write"))
    }

    @Test("the job that runs the pull request's code has no token, in its environment or in a step")
    func theRecordJobHasNoToken() throws {
        let record = try job("record")
        #expect(record.steps.contains { $0.script.contains("make snapshots") })
        #expect(record.steps.contains { $0.script.contains(".github/scripts/pack-references.sh") })
        for secret in ["github.token", "secrets.", "GH_TOKEN", "GITHUB_TOKEN"] {
            #expect(!record.text.contains(secret), "the record job mentions \(secret)")
        }
        #expect(record.text.contains("contents: read"))
    }

    @Test("in the job that can write, the token is in one step: the one that pushes and starts CI")
    func theTokenIsInOneStep() throws {
        let file = try recordWorkflow()
        let commit = try job("commit")
        let holders = commit.steps.filter { $0.text.contains("github.token") }
        #expect(holders.map(\.name) == ["Push and start CI"])
        // The guard reads pull requests with a token that cannot write, and no other job has one.
        let others = file.jobs.filter { $0.id != "commit" }.filter { $0.text.contains("github.token") }
        #expect(others.map(\.id) == ["target"])
        #expect(try job("target").text.contains(": write") == false)
        #expect(!file.header.contains("github.token"))
        #expect(!file.text.contains("secrets."))
    }

    @Test("the job that writes runs scripts of the repository and no build tool")
    func theCommitJobRunsNoBuild() throws {
        let commit = try job("commit")
        let scripts = commit.steps.map(\.script).joined(separator: "\n")
        for tool in ["make ", "swift ", "xcodebuild", "xcrun", "brew ", "npm ", "pip ", "cargo "] {
            #expect(!scripts.contains(tool), "the commit job runs \(tool)")
        }
        #expect(scripts.contains(".github/scripts/commit-references.sh"))
        #expect(scripts.contains(".github/scripts/publish-references.sh"))
    }

    @Test("recording waits for the guard, and every job works on the commit the guard found")
    func jobsFollowTheGuard() throws {
        let target = try job("target")
        #expect(target.text.contains("pull-requests: read"))
        #expect(target.steps.contains { $0.script.contains(".github/scripts/guard-record-target.sh") })
        for id in ["record", "commit"] {
            let job = try job(id)
            #expect(job.text.contains("needs:") && job.text.contains("target"), "\(id) does not wait for the guard")
            let checkout = try #require(job.steps.first { $0.uses?.hasPrefix("actions/checkout@") == true })
            #expect(
                checkout.text.contains("ref: ${{ needs.target.outputs.sha }}"), "\(id) does not use the found commit")
        }
        #expect(try job("commit").text.contains("record"))
    }

    @Test("a branch name is read from the environment, never from the trigger inside a script")
    func theBranchComesFromTheEnvironment() throws {
        let target = try job("target")
        let guardStep = try #require(target.steps.first { $0.script.contains("guard-record-target.sh") })
        for variable in ["REPO:", "BRANCH:", "DEFAULT_BRANCH:"] {
            #expect(guardStep.text.contains(variable), "the guard step lacks \(variable)")
        }
        #expect(guardStep.text.contains("github.event.repository.default_branch"))
    }

    // MARK: What a failure leaves behind

    private static let snapshotSteps: [(path: String, job: String, step: String)] = [
        (ci, "verify", "Snapshots"), (record, "record", "Check against the new references"),
    ]

    @Test("the image the job ran on is in its log", arguments: snapshotSteps)
    func logsTheImage(path: String, job: String, step: String) throws {
        let found = try #require(try workflow(path).job(job))
        let scripts = found.steps.map(\.script).joined(separator: "\n")
        #expect(scripts.contains("sw_vers"))
        #expect(scripts.contains("xcodebuild -version"))
    }

    @Test(
        "a failing snapshot step names a folder for its pictures, and the folder is uploaded", arguments: snapshotSteps)
    func uploadsTheFailures(path: String, job: String, step: String) throws {
        let found = try #require(try workflow(path).job(job))
        let snapshots = try #require(found.step(named: step), "\(path) has no step \(step)")
        #expect(snapshots.text.contains("SNAPSHOT_ARTIFACTS:"))
        let upload = try #require(
            found.steps.first {
                $0.uses?.hasPrefix("actions/upload-artifact@") == true && $0.text.contains("snapshot-failures")
            },
            "\(path) uploads no failure pictures")
        #expect(upload.condition == "failure()")
        #expect(upload.text.contains("runner.temp"))
        #expect(upload.text.contains("if-no-files-found: ignore"))
    }
}
