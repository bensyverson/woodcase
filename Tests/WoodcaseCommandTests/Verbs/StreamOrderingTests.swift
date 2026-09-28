//
//  StreamOrderingTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// What a verb looks like when both of its streams go to one terminal — an agent's
/// usual case, and the only one where the two can interleave.
///
/// `print` goes through C `stdio`, fully buffered anywhere but a terminal; standard
/// error is unbuffered. So a verb that prints a table and then warns about it emitted
/// the warning *first*, and `tree`'s `--props` advisory landed inside a table row.
/// ``StandardErrorLine`` flushes standard output before every message, which is what
/// these runs check: not that the advisory exists, but that the table is whole when it
/// arrives.
@Suite("Stream ordering on a shared terminal")
struct StreamOrderingTests {
    /// Runs the binary with both streams pointed at one file, the way a terminal
    /// merges them, and returns what that file holds.
    ///
    /// ``CommandFixture/run(_:environment:stdin:)`` collects the two separately —
    /// which is right for every other test and useless for this one, because the
    /// separation is exactly what hides the bug.
    private func runMerged(_ fixture: CommandFixture, _ arguments: [String]) throws -> String {
        let merged = fixture.root.appendingPathComponent("merged-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: merged.path, contents: nil)
        let handle = try FileHandle(forWritingTo: merged)

        var environment = ProcessInfo.processInfo.environment
        environment[ActivityLog.homeEnvironmentVariable] = fixture.home.path
        environment["HOME"] = fixture.root.path

        let process = Process()
        process.executableURL = try CommandFixture.binary()
        process.arguments = arguments
        process.currentDirectoryURL = fixture.root
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try handle.close()

        return (try? String(contentsOf: merged, encoding: .utf8)) ?? ""
    }

    @Test("The --props advisory follows the whole table rather than landing inside it")
    func propsAdvisoryFollowsTheTable() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        // "content" is the unprefixed spelling of "kind.content" — a typo that reads as
        // an answer, which is why the advisory exists.
        let merged = try runMerged(fixture, ["tree", fixture.file.path, "--props", "content"])

        var lines = merged.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        let advisory = try #require(lines.firstIndex { $0.hasPrefix("--props:") })

        // Everything before it is the report: the header, the column names and 9 rows.
        #expect(advisory == lines.count - 1)
        #expect(lines[0].hasPrefix("rev "))
        #expect(lines.count == 12)
    }

    @Test("Separated, the two streams still carry what they always did")
    func separatedStreamsAreUnchanged() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--props", "content")

        #expect(run.status == 0)
        #expect(run.stderr.hasPrefix("--props:"))
        #expect(!run.stdout.contains("--props:"))
    }
}
