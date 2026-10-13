import Foundation

/// A GitHub Actions workflow read as text, only far enough to ask what a job and a step contain. It reads the layout
/// these workflows are written in (jobs at two spaces, steps at six), and a file in another layout reads as having no
/// jobs, which the policy tests report.
struct WorkflowFile {
    struct Step {
        let text: String

        var name: String? { value(of: "name") }
        var uses: String? { value(of: "uses") }
        var condition: String? { value(of: "if") }

        /// The script of a `run:` step, with its indentation removed. Empty when the step does not run one.
        var script: String {
            let lines = text.components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("run:") })
            else { return "" }
            let indent = lines[start].prefix { $0 == " " || $0 == "-" }.count
            let first = lines[start].drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
            var body = first == "|" || first == ">" ? [] : [first]
            for line in lines[(start + 1)...] {
                let lineIndent = line.prefix { $0 == " " }.count
                if !line.trimmingCharacters(in: .whitespaces).isEmpty && lineIndent <= indent { break }
                body.append(line.trimmingCharacters(in: .whitespaces))
            }
            return body.joined(separator: "\n")
        }

        private func value(of key: String) -> String? {
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "- ", with: "")
                if trimmed.hasPrefix("\(key):") {
                    return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
    }

    struct Job {
        let id: String
        let text: String
        let steps: [Step]

        func step(named name: String) -> Step? { steps.first { $0.name == name } }
    }

    let text: String
    let jobs: [Job]

    init(_ path: String) throws {
        text = try String(contentsOf: PackageLayout.repositoryFile(path), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "jobs:") else {
            jobs = []
            return
        }
        var found: [Job] = []
        var current: (id: String, lines: [String])?
        for line in lines[(start + 1)...] {
            if let id = Self.jobID(in: line) {
                if let current { found.append(Self.job(current.id, current.lines)) }
                current = (id, [])
            } else if !line.isEmpty, !line.hasPrefix(" ") {
                break
            } else {
                current?.lines.append(line)
            }
        }
        if let current { found.append(Self.job(current.id, current.lines)) }
        jobs = found
    }

    func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

    /// The text before `jobs:`: the triggers, the permissions, and the settings every job shares.
    var header: String {
        text.components(separatedBy: "\njobs:").first ?? text
    }

    /// `  name:` at two spaces of indentation and nothing after the colon.
    private static func jobID(in line: String) -> String? {
        guard line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") else { return nil }
        return String(line.dropFirst(2).dropLast())
    }

    private static func job(_ id: String, _ lines: [String]) -> Job {
        var steps: [Step] = []
        var current: [String]?
        var inSteps = false
        for line in lines {
            if line == "    steps:" {
                inSteps = true
            } else if inSteps, line.hasPrefix("      - ") {
                if let current { steps.append(Step(text: current.joined(separator: "\n"))) }
                current = [line]
            } else if inSteps {
                current?.append(line)
            }
        }
        if let current { steps.append(Step(text: current.joined(separator: "\n"))) }
        return Job(id: id, text: lines.joined(separator: "\n"), steps: steps)
    }
}
