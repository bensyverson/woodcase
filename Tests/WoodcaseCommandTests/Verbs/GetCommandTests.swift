//
//  GetCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase get` — one node, as .pen JSON, with the revision a write must quote.
@Suite("woodcase get")
struct GetCommandTests {
    // MARK: - The node and its revision

    @MainActor
    @Test("The node's revision heads the output and its .pen JSON follows")
    func revisionAlongsideJSON() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Title")
        let revision = try Self.revision(of: "Ttl01", in: fixture)

        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines[0] == "Ttl01  Canvas/Title  rev \(revision)")

        let body = lines.dropFirst().joined(separator: "\n")
        let node = try JSONDecoder().decode(PenNode.self, from: Data(body.utf8))
        #expect(node.id == "Ttl01")
        #expect(node.common.name == "Title")
    }

    @Test("The JSON is canonical: sorted keys, two-space indent, tightened colons")
    func canonicalJSON() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Title")

        #expect(run.stdoutLines[1] == "{")
        #expect(run.stdoutLines.contains(#"  "id": "Ttl01","#))
        #expect(run.stdoutLines.last == "}")
        // Sorted keys: content, id, name, type.
        let keys = run.stdoutLines.compactMap { line -> String? in
            guard line.hasPrefix(#"  ""#), let end = line.dropFirst(3).firstIndex(of: "\"") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 3) ..< end])
        }
        #expect(keys == keys.sorted())
    }

    @Test("The stored node is printed without its children — tree is the structural read")
    func storedNodeHasNoChildren() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Canvas")

        #expect(run.status == 0)
        #expect(!run.stdout.contains("\"children\""))
        #expect(run.stdout.contains("\"id\": \"Cnv01\""))
    }

    // MARK: - JSON

    @MainActor
    @Test("--json wraps the node and its revision in one object")
    func jsonWrapsRevisionAndNode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Title", "--json")
        let revision = try Self.revision(of: "Ttl01", in: fixture)

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.revision == revision)
        #expect(report.node.id == "Ttl01")
    }

    @Test("The revision moves with the node and stays put for a sibling's edit")
    func revisionIsPerNode() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try fixture.run("get", fixture.file.path, "Title", "--json")

        try Self.replace("\"content\": \"chip\"", with: "\"content\": \"CHIP\"", in: fixture.file)
        let afterSibling = try fixture.run("get", fixture.file.path, "Title", "--json")
        #expect(afterSibling.stdout == before.stdout)

        try Self.replace("\"content\": \"Canvas\"", with: "\"content\": \"Board\"", in: fixture.file)
        let afterSelf = try fixture.run("get", fixture.file.path, "Title", "--json")
        #expect(afterSelf.stdout != before.stdout)
    }

    // MARK: - Expansion

    @Test("--expand prints the instance as it renders, ids prefixed by the ref")
    func expandsAnInstance() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--expand", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.node.id == "Chi01/Cmp01")
        guard case let .frame(data) = report.node.kind else {
            Issue.record("expanded instance is not a frame")
            return
        }
        #expect(data.children?.map(\.id) == ["Chi01/Lbl01"])
    }

    @Test("Without --expand a ref prints as the ref it is")
    func refWithoutExpansion() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--json")

        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.node.id == "Chi01")
        guard case let .ref(data) = report.node.kind else {
            Issue.record("Chip is not a ref")
            return
        }
        #expect(data.ref == "Cmp01")
    }

    @MainActor
    @Test("An address inside an instance reads the node with its overrides applied")
    func instanceDescendant() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("get", fixture.file.path, "Nav/Badge/Count", "--json")
        let revision = try Self.revision(of: "Nav01", in: fixture)

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        #expect(report.node.id == "Nav01/Bdg01/Cnt01")
        guard case let .text(data) = report.node.kind else {
            Issue.record("Count is not text")
            return
        }
        #expect(data.content?.literalValue == "3")
        #expect(report.revision == revision)
    }

    // MARK: - Errors

    @Test("An address that names nothing exits 2 and lists near misses")
    func unknownAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.file.path, "Nope")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Nope"))
    }

    @Test("An ambiguous address exits 2 and lists every candidate")
    func ambiguousAddressIsUsage() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("get", fixture.file.path, "Title")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Ttl01"))
        #expect(run.stderr.contains("Ttl02"))
    }

    @Test("A file that is not there exits 4")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", fixture.root.appendingPathComponent("gone.pen").path, "Title")

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("gone.pen"))
    }

    @Test("A read leaves the file's bytes exactly as they were")
    func readsNeverWrite() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        _ = try fixture.run("get", fixture.file.path, "Chip", "--expand")

        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - Help

    @Test("get --help says --json nests the node under \"node\" beside \"revision\"")
    func helpNamesTheJSONShape() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("get", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("\"node\""))
        #expect(run.stdout.contains("\"revision\""))
    }

    // MARK: - Helpers

    /// The revision the library computes for a node, so the test asserts against the
    /// same source of truth a later `--rev` will be checked against.
    @MainActor
    private static func revision(of nodeID: String, in fixture: CommandFixture) throws -> String {
        let parsed = try PenParser.parse(contentsOf: fixture.file)
        return try #require(EditableDocument(from: parsed).revision(of: nodeID))
    }

    /// Rewrites one literal in the fixture's copy, failing loudly if it is not there.
    private static func replace(_ text: String, with replacement: String, in file: URL) throws {
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents.contains(text), "fixture no longer contains \(text)")
        try contents
            .replacingOccurrences(of: text, with: replacement)
            .write(to: file, atomically: true, encoding: .utf8)
    }
}
