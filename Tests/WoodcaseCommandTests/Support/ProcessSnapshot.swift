//
//  ProcessSnapshot.swift
//  WoodcaseCommandTests
//

import Foundation
import Woodcase

/// What `ps` and `sample` say about a process a test expected to be gone.
///
/// A test that only records "still alive" leaves the next reader to guess whether the
/// process was hung, still working, or never told to stop. Its parent id says whether
/// it was orphaned at all, its state whether it was running or asleep, and a short
/// `sample` where it was sleeping — enough for the failure to name its own cause.
struct ProcessSnapshot: Friendly {
    /// `ps`'s one-line view: pid, parent, process group, state, elapsed time, command.
    let ps: String

    /// The head of a one-second `sample` call graph, or why there is none.
    let sample: String

    /// How many lines of `sample`'s report to keep; the call graph comes first.
    static let sampleLines = 60

    /// Takes a snapshot of `pid`, writing scratch output under `directory`.
    ///
    /// Both tools are bounded, so a snapshot never turns a failure into a hang.
    ///
    /// - Parameters:
    ///   - pid: The process to describe.
    ///   - directory: Where the tools' output may be written.
    /// - Returns: Whatever the tools could say.
    static func take(of pid: pid_t, in directory: URL) async -> ProcessSnapshot {
        let ps = await run(
            "/bin/ps", ["-o", "pid,ppid,pgid,stat,etime,command", "-p", "\(pid)"],
            output: directory.appendingPathComponent("snapshot-ps.txt")
        )
        // `-file` keeps the report in the fixture; without it `sample` leaves one in /tmp.
        let report = directory.appendingPathComponent("snapshot-sample-report.txt")
        let tool = await run(
            "/usr/bin/sample", ["\(pid)", "1", "-mayDie", "-file", report.path],
            output: directory.appendingPathComponent("snapshot-sample.txt")
        )
        guard let text = try? String(contentsOf: report, encoding: .utf8) else {
            return ProcessSnapshot(ps: ps, sample: "no report: \(tool)")
        }
        // The header above the call graph is the process's identity, which `ps` has said.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let graph = lines.drop { !$0.hasPrefix("Call graph:") }
        return ProcessSnapshot(
            ps: ps,
            sample: (graph.isEmpty ? lines[...] : graph).prefix(sampleLines).joined(separator: "\n")
        )
    }

    /// Runs a tool into a file and returns what it wrote, or why it could not.
    ///
    /// - Parameters:
    ///   - tool: The executable's path.
    ///   - arguments: Its arguments.
    ///   - output: The file to collect standard output and error in.
    /// - Returns: The tool's output.
    private static func run(_ tool: String, _ arguments: [String], output: URL) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        FileManager.default.createFile(atPath: output.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: output)
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
        } catch {
            return "could not run \(tool): \(error)"
        }
        let finished = await PollingWait(bound: .seconds(20), poll: .milliseconds(50)).until {
            !process.isRunning
        }
        if !finished.satisfied {
            process.terminate()
            return "\(tool) did not finish in 20 s"
        }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? "\(tool) wrote nothing readable"
    }
}
