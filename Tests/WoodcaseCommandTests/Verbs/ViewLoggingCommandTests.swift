//
//  ViewLoggingCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A read verb run with an identity records what it read in `views.jsonl` — never in
/// the activity log — and one run without an identity records nothing. A views write
/// that fails never fails the read.
struct ViewLoggingCommandTests {
    private func views(_ fixture: CommandFixture) throws -> [ViewEvent] {
        try ViewReader(log: ViewLog(home: fixture.home)).read().events
    }

    /// The revision a `tree` header carries.
    private func documentRevision(_ fixture: CommandFixture) throws -> String {
        let run = try fixture.run("tree", fixture.file.path, "--depth", "0")
        let header = try #require(run.stdoutLines.first)
        return String(header.split(separator: " ")[1])
    }

    private func id(of address: String, _ fixture: CommandFixture) throws -> String {
        let run = try fixture.run("get", fixture.file.path, address)
        let header = try #require(run.stdoutLines.first)
        return String(header.split(separator: " ")[0])
    }

    @Test("An attributed get records the node and the document revision")
    func attributedGetRecords() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let plain = try fixture.run("get", fixture.file.path, "Canvas/Title")

        let run = try fixture.run("get", fixture.file.path, "Canvas/Title", "--as", "claude")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == plain.stdout, "--as must not change what a read prints")
        let view = try #require(try views(fixture).first)
        #expect(try views(fixture).count == 1)
        #expect(view.identity == "claude")
        #expect(view.verb == .get)
        #expect(try view.nodes == [id(of: "Canvas/Title", fixture)])
        // A plain get prints the node without its children.
        #expect(view.scope == .nodes)
        #expect(try view.revision == documentRevision(fixture))
        #expect(view.file == ActivityEvent.canonicalPath(for: fixture.file))
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path), "a view is not activity")
    }

    @Test("An attributed get --expand records the node's subtree")
    func attributedExpandedGetRecordsTheSubtree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Canvas", "--expand", "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try views(fixture).map(\.scope) == [.subtrees])
    }

    @Test("An attributed tree records the rows it printed, and how many")
    func attributedTreeRecords() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json", "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")

        let report = try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        let rows = try #require(report?["rows"] as? [[String: Any]])
        let ids = rows.compactMap { $0["id"] as? String }
        let view = try #require(try views(fixture).first)
        #expect(view.verb == .tree)
        #expect(view.nodes == Array(ids.prefix(ViewEvent.nodeLimit)))
        #expect(view.covered == ids.count)
        #expect(view.scope == .nodes)
        #expect(view.revision == report?["revision"] as? String)
    }

    @Test("$WOODCASE_AS names the reader when --as is absent")
    func environmentNamesTheReader() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            ["get", fixture.file.path, "Canvas/Title"], environment: [Identity.environmentVariable: "claude"]
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try views(fixture).map(\.identity) == ["claude"])
    }

    @Test("An unattributed read records nothing", arguments: [
        ["tree"], ["get", "Canvas/Title"], ["find", "r => r.type === 'text'"],
    ])
    func unattributedReadRecordsNothing(verb: [String]) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run([verb[0], fixture.file.path] + verb.dropFirst())
        #expect(run.status == 0, "\(run.stderr)")
        #expect(!FileManager.default.fileExists(atPath: ViewLog(home: fixture.home).fileURL.path))
    }

    @Test("An attributed find records its matches")
    func attributedFindRecords() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("find", fixture.file.path, "r => r.name === 'Title'", "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")
        let view = try #require(try views(fixture).first)
        #expect(view.verb == .find)
        #expect(try view.nodes == [id(of: "Canvas/Title", fixture)])
    }

    @Test("An attributed shot records the node and every outline, with their subtrees")
    func attributedShotRecords() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let out = fixture.root.appendingPathComponent("shot.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Canvas", "--outline", "Canvas/Title", "--out", out, "--as", "claude"
        )
        #expect(run.status == 0, "\(run.stderr)")
        let view = try #require(try views(fixture).first)
        #expect(view.verb == .shot)
        #expect(try view.nodes == [id(of: "Canvas", fixture), id(of: "Canvas/Title", fixture)])
        #expect(view.scope == .subtrees)
    }

    @Test("An attributed render records the roots it drew")
    func attributedRenderRecords() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            "render", fixture.file.path, "--output-dir", fixture.root.path, "--as", "claude"
        )
        #expect(run.status == 0, "\(run.stderr)")
        let view = try #require(try views(fixture).first)
        #expect(view.verb == .render)
        #expect(try view.nodes.contains(id(of: "Canvas", fixture)))
        #expect(view.scope == .subtrees)
    }

    @Test("A views write that fails does not fail the read")
    func failingViewsWriteIsIgnored() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        // A directory where the file should be: every open for writing fails.
        try FileManager.default.createDirectory(
            at: ViewLog(home: fixture.home).fileURL, withIntermediateDirectories: true
        )
        let plain = try fixture.run("get", fixture.file.path, "Canvas/Title")

        let run = try fixture.run("get", fixture.file.path, "Canvas/Title", "--as", "claude")

        #expect(run.status == 0)
        #expect(run.stdout == plain.stdout)
        #expect(run.stderr == plain.stderr)
    }
}
