//
//  TextSpansCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Rich text from a shell: `add` and `set` write `metadata.woodcase.spans`, `tree` and `get`
/// report it, `lint` names stale spans, and a `set` that leaves spans stale says so.
///
/// `text-spans.pen` holds three texts: `Styled`, whose spans match its content; `Stale`,
/// whose content was edited after its spans were made; and `Plain`, with none.
@Suite("woodcase spans on the command line")
struct TextSpansCommandTests {
    private static let bold = #"{"text":"Nothing styled","runs":[{"start":8,"end":14,"fontWeight":"700"}]}"#

    private func spans(of node: String, in fixture: CommandFixture) throws -> PenTextSpans? {
        try PenFileProbe(fixture.file).node(node)?.textSpans
    }

    @Test("set writes spans through the namespace, typed and read back")
    func setWritesSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run(
            "set", fixture.file.path, "Board/Plain", "kind.spans=\(Self.bold)", "--as", "ana"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stderr.isEmpty)
        let node = try #require(PenFileProbe(fixture.file).node("Board/Plain"))
        #expect(node.common.metadata?.type == PenMetadata.woodcaseType)
        #expect(node.appliedRuns == [PenTextRun(start: 8, end: 14, fontWeight: 700)])
    }

    @Test("set refuses spans Woodcase cannot draw, naming the problem")
    func setRefusesMalformedSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let malformed = #"{"text":"Nothing styled","runs":[{"start":0,"end":4,"bold":true}]}"#
        let run = try fixture.run(
            "set", fixture.file.path, "Board/Plain", "kind.spans=\(malformed)"
        )
        #expect(run.status != 0)
        #expect(run.stderr.contains("unknown key \"bold\""), "\(run.stderr)")
        #expect(try spans(of: "Board/Plain", in: fixture) == nil)
    }

    @Test("set warns when it changes content its spans were made for")
    func setWarnsWhenSpansGoStale() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run("set", fixture.file.path, "Board/Styled", "kind.content=Make this BOLD")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stderr.contains("spans-stale"), "\(run.stderr)")
        #expect(run.stderr.contains("Styled"))
        // The spans stay, ignored: the write does not guess at moving them.
        #expect(try spans(of: "Board/Styled", in: fixture)?.text == "Make this bold")
    }

    @Test("set says nothing when content and spans change together, or spans were stale already")
    func setQuietWhenSpansFollow() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let together = try fixture.run(
            "set", fixture.file.path, "Board/Plain", "kind.content=All styled",
            #"kind.spans={"text":"All styled","runs":[{"start":0,"end":3,"fontStyle":"italic"}]}"#
        )
        #expect(together.status == 0, "\(together.stderr)")
        #expect(together.stderr.isEmpty, "\(together.stderr)")
        let already = try fixture.run("set", fixture.file.path, "Board/Stale", "kind.content=Still stale")
        #expect(already.status == 0)
        #expect(already.stderr.isEmpty, "\(already.stderr)")
    }

    @Test("add writes a text node's spans")
    func addWritesSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let subtree = fixture.root.appendingPathComponent("styled.json")
        try #"""
        {"type":"text","name":"New","content":"Hi there",
         "metadata":{"woodcase":{"spans":{"text":"Hi there","runs":[{"start":0,"end":2,"fill":"#FF0000"}]}}}}
        """#.write(to: subtree, atomically: true, encoding: .utf8)
        let run = try fixture.run("add", fixture.file.path, "Board", "-F", subtree.path, "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        let node = try #require(PenFileProbe(fixture.file).node("Board/New"))
        #expect(node.appliedRuns == [PenTextRun(start: 0, end: 2, fill: PenHexColor(red: 255, green: 0, blue: 0))])
        #expect(node.common.metadata?.type == PenMetadata.woodcaseType)
    }

    @Test("add refuses malformed spans")
    func addRefusesMalformedSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let subtree = fixture.root.appendingPathComponent("broken.json")
        try #"""
        {"type":"text","name":"New","content":"Hi",
         "metadata":{"woodcase":{"spans":{"text":"Hi","runs":[{"start":0,"end":9}]}}}}
        """#.write(to: subtree, atomically: true, encoding: .utf8)
        let run = try fixture.run("add", fixture.file.path, "Board", "-F", subtree.path)
        #expect(run.status != 0)
        #expect(run.stderr.contains("run 1"), "\(run.stderr)")
    }

    @Test("tree marks styled text with its run count, and stale spans")
    func treeReportsSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run("tree", fixture.file.path)
        #expect(run.status == 0)
        let lines = run.stdout.split(separator: "\n").map(String.init)
        #expect(lines.first { $0.contains("Sty01") }?.contains("Styled [2 runs]") == true, "\(run.stdout)")
        #expect(lines.first { $0.contains("Stl01") }?.contains("Stale ⚠ stale runs") == true, "\(run.stdout)")
        #expect(lines.first { $0.contains("Pln01") }?.contains("[") == false)
    }

    @Test("tree --json carries each text's spans")
    func treeJSONReportsSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run("tree", fixture.file.path, "--json")
        #expect(run.status == 0)
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let rows = Dictionary(uniqueKeysWithValues: report.rows.map { ($0.id, $0) })
        #expect(rows["Sty01"]?.spans == TreeRow.Spans(runs: 2, isStale: false))
        #expect(rows["Stl01"]?.spans == TreeRow.Spans(runs: 1, isStale: true))
        #expect(rows["Pln01"]?.spans == nil)
    }

    @Test("get prints a text's spans with the node")
    func getReportsSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run("get", fixture.file.path, "Board/Styled")
        #expect(run.status == 0)
        #expect(run.stdout.contains("\"spans\""))
        #expect(run.stdout.contains("\"fontWeight\""))
        #expect(run.stdout.contains("\"700\""))
    }

    @Test("lint names stale spans, and only those")
    func lintReportsStaleSpans() throws {
        let fixture = try CommandFixture(fixture: "text-spans.pen")
        let run = try fixture.run("lint", fixture.file.path)
        let findings = run.stdout.split(separator: "\n").filter { $0.contains("spans-stale") }
        #expect(findings.count == 1, "\(run.stdout)")
        #expect(findings.first?.contains("Stl01") == true)
    }
}
