//
//  ScriptReadParityTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
import WoodcaseScripting

/// `doc.tree`, `doc.get`, `doc.lint` and `doc.schema` answer exactly what the matching
/// verb prints with `--json`.
///
/// The suite lives here, in the command tests, rather than beside the host: only a target
/// that can both launch the real `woodcase` binary *and* call `ScriptHost` can ask the
/// question the criterion asks. Comparing the host's answer against the bytes the process
/// printed is a stronger claim than comparing two in-process calls, which could agree by
/// sharing a bug.
///
/// The comparison is on parsed JSON, not on bytes: the CLI pretty-prints and the host does
/// not, and pretty-printing is a fact about a terminal, not about the answer.
@Suite("doc's reads match the verbs")
struct ScriptReadParityTests {
    /// The fixture both sides read.
    private let fixture: CommandFixture

    /// Copies `batch.pen` for this suite.
    init() throws {
        fixture = try CommandFixture(fixture: "batch.pen")
    }

    /// What the verb printed with `--json`, parsed.
    private func verb(_ arguments: String...) throws -> AnyCodable {
        let run = try fixture.run(arguments + ["--json"])
        #expect(run.status == 0 || run.status == 1, "the verb failed: \(run.stderr)")
        return try JSONDecoder().decode(AnyCodable.self, from: Data(run.stdout.utf8))
    }

    /// What a script answered, parsed.
    private func script(_ expression: String) throws -> AnyCodable {
        let document = try EditableDocument(from: PenParser.parse(contentsOf: fixture.file))
        let run = ScriptHost.run([.text(expression, name: "<parity>")], over: document)
        #expect(run.error == nil, "the script failed: \(run.error?.message ?? "")")
        return try #require(run.result)
    }

    // MARK: - tree

    @Test("doc.tree() equals the rows of tree --json")
    func treeMatches() throws {
        let printed = try verb("tree", fixture.file.path)
        guard case let .dictionary(report) = printed else {
            Issue.record("tree --json should be an object")
            return
        }
        #expect(try script("doc.tree()") == report["rows"])
        let revision = try stringResult(of: "doc.rev")
        #expect(try report["revision"] == .string(#require(revision)))
    }

    @Test("doc.tree with a subtree, a depth and expansion equals the verb's rows")
    func treeOptionsMatch() throws {
        let printed = try verb("tree", fixture.file.path, "Brd01", "--depth", "1", "--expand")
        guard case let .dictionary(report) = printed else {
            Issue.record("tree --json should be an object")
            return
        }
        let answered = try script("doc.tree('Brd01', { depth: 1, expand: true })")
        #expect(answered == report["rows"])
    }

    @Test("doc.tree with props equals the verb's rows")
    func treePropsMatch() throws {
        let printed = try verb("tree", fixture.file.path, "--props", "kind.content,kind.layout")
        guard case let .dictionary(report) = printed else {
            Issue.record("tree --json should be an object")
            return
        }
        let answered = try script("doc.tree(null, { props: ['kind.content', 'kind.layout'] })")
        #expect(answered == report["rows"])
    }

    // MARK: - get

    @Test("doc.get equals get --json")
    func getMatches() throws {
        #expect(try script("doc.get('Cnv01')") == verb("get", fixture.file.path, "Cnv01"))
    }

    @Test("doc.get with expand equals get --expand --json")
    func getExpandedMatches() throws {
        let printed = try verb("get", fixture.file.path, "Chi01", "--expand")
        #expect(try script("doc.get('Chi01', { expand: true })") == printed)
    }

    // MARK: - lint

    @Test("doc.lint equals lint --json")
    func lintMatches() throws {
        #expect(try script("doc.lint()") == verb("lint", fixture.file.path))
    }

    @Test("doc.lint with exclude and severity equals the verb's findings")
    func lintFiltersMatch() throws {
        let printed = try verb("lint", fixture.file.path, "--exclude", "clipped", "--severity", "error")
        let answered = try script("doc.lint(null, { exclude: ['clipped'], severity: 'error' })")
        #expect(answered == printed)
    }

    // MARK: - schema

    @Test("doc.schema() equals schema --json")
    func schemaOverviewMatches() throws {
        #expect(try script("doc.schema()") == verb("schema"))
    }

    @Test("doc.schema(type) equals schema <type> --json for every node type")
    func schemaTypesMatch() throws {
        for type in PenNode.NodeType.allCases.map(\.rawValue) {
            #expect(
                try script("doc.schema('\(type)')") == verb("schema", type),
                "doc.schema('\(type)') diverged from `woodcase schema \(type) --json`"
            )
        }
    }

    // MARK: - Helpers

    /// A script's answer, when it is a plain string.
    private func stringResult(of expression: String) throws -> String? {
        guard case let .string(text) = try script(expression) else { return nil }
        return text
    }
}
