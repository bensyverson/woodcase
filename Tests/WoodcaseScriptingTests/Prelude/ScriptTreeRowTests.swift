//
//  ScriptTreeRowTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// The rows `doc.tree` hands a script are the rows a `find` predicate sees.
///
/// One row view, two routes. The trap this suite exists for is the one `find` closed and
/// `doc.tree` left open: `r.props['kind.fontSize']` — the spelling `find` teaches — read
/// `undefined` on the plain object `JSON.parse` built, `undefined < 12` is `false`, and a
/// filter that matched nothing was a script that wrote nothing and exited 0.
@Suite("doc.tree's rows refuse what find's refuse")
struct ScriptTreeRowTests {
    /// Runs one script over `batch.pen`.
    private func run(_ text: String) throws -> ScriptRun {
        let document = try ScriptFixture.document("batch.pen")
        return ScriptHost.run(
            [.text(text, name: "<argv>")],
            over: document,
            remedy: .command(file: "design.pen")
        )
    }

    /// The failure one script ended with.
    private func failure(of text: String) throws -> ScriptError {
        try #require(run(text).error, "\(text) should have thrown")
    }

    // MARK: - The columns

    @Test("r.props reads a column the props option asked for")
    func propsReadsARequestedColumn() throws {
        let run = try run(
            "doc.tree(null, { props: ['kind.content'] })"
                + ".filter(r => r.props['kind.content'] === 'Canvas').map(r => r.id)"
        )

        #expect(run.error == nil)
        #expect(run.result == .array([.string("Ttl01")]))
    }

    @Test("a requested column a row does not carry is undefined, not a refusal")
    func aRequestedColumnMayBeAbsent() throws {
        // A frame has no kind.fontSize at all, so the bag simply does not carry the key —
        // that is a real answer about the node, not a mistake about the question.
        let run = try run(
            "doc.tree(null, { props: ['kind.fontSize'] })"
                + ".filter(r => r.props['kind.fontSize'] === undefined).length"
        )

        #expect(run.error == nil)
        guard case let .int(absent) = run.result else {
            Issue.record("the count did not cross: \(String(describing: run.result))")
            return
        }
        #expect(absent > 0)
    }

    @Test("r.props with no props option refuses, naming the option that would fill it")
    func propsWithoutColumnsRefuses() throws {
        let error = try failure(of: "doc.tree().filter(r => r.props['kind.fontSize'] < 12)")

        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("props: ['kind.fontSize']"))
        #expect(error.message.contains("doc.tree"))
        #expect(!error.message.contains("--props"))
    }

    @Test("a path outside the requested columns refuses, listing the ones asked for")
    func anUnrequestedPathRefuses() throws {
        let error = try failure(
            of: "doc.tree(null, { props: ['kind.content'] })"
                + ".filter(r => r.props['kind.fontSize'] < 12)"
        )

        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("kind.content"))
        #expect(error.message.contains("the props option"))
    }

    @Test("r.properties — the row's own key — reads the same guarded view")
    func propertiesIsTheSameView() throws {
        let kept = try run(
            "doc.tree(null, { props: ['kind.content'] })"
                + ".filter(r => r.properties['kind.content'] === 'Canvas').map(r => r.id)"
        )
        #expect(kept.error == nil)
        #expect(kept.result == .array([.string("Ttl01")]))

        let refused = try failure(
            of: "doc.tree(null, { props: ['kind.content'] })"
                + ".filter(r => r.properties['kind.fontSize'] < 12)"
        )
        #expect(refused.code == ScriptErrorCode.unknownMember)
        #expect(refused.message.contains("r.properties"))
    }

    // MARK: - The members

    @Test("a property read straight off the row refuses, listing the members a row carries")
    func anUnknownMemberListsTheMembers() throws {
        let error = try failure(of: "doc.tree().filter(r => r.fontSize < 12)")

        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("a row has no fontSize"))
        for member in ["type", "address", "rect", "absRect", "depth", "childCount"] {
            #expect(error.message.contains(member), "the sentence should list \(member)")
        }
        #expect(error.message.contains("props: ['kind.fontSize']"))
    }

    @Test("the refusal is a WoodcaseError a script can catch, like every other")
    func theRefusalIsCatchable() throws {
        let run = try run(
            """
            try { doc.tree()[0].fontSize; } catch (e) {
              ({ caught: e instanceof WoodcaseError, code: e.code });
            }
            """
        )

        #expect(run.error == nil)
        #expect(run.result == .dictionary([
            "caught": .bool(true),
            "code": .string(ScriptErrorCode.unknownMember),
        ]))
    }

    // MARK: - A row is still a value

    @Test("a run that ends in doc.tree still answers with the rows as JSON")
    func theRowsStillCross() throws {
        let run = try run("doc.tree('Cnv01')")

        #expect(run.error == nil)
        guard case let .array(rows) = run.result else {
            Issue.record("doc.tree did not cross as an array: \(String(describing: run.result))")
            return
        }
        #expect(rows.count == 5)
        guard case let .dictionary(first) = rows[0] else {
            Issue.record("a row did not cross as an object")
            return
        }
        #expect(first["id"] == .string("Cnv01"))
        #expect(first["type"] == .string("frame"))
    }

    @Test("the rows are the same JSON the plain rows encode to, columns included")
    func theRowsMatchTheLibrarysOwn() throws {
        let document = try ScriptFixture.document("batch.pen")
        let rows = try TreeView.rows(of: document, properties: ["kind.content"])
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(rows)
        ) as? [[String: Any]]

        let run = ScriptHost.run(
            [.text("doc.tree(null, { props: ['kind.content'] })", name: "<argv>")],
            over: document
        )

        let answered = try #require(run.result)
        let json = try JSONEncoder().encode(answered)
        let object = try JSONSerialization.jsonObject(with: json) as? [[String: Any]]
        #expect(object?.count == encoded?.count)
        #expect(
            object?.compactMap { $0["id"] as? String } == encoded?.compactMap { $0["id"] as? String }
        )
        #expect(
            object?.compactMap { ($0["properties"] as? [String: Any])?["kind.content"] as? String }
                == encoded?.compactMap { ($0["properties"] as? [String: Any])?["kind.content"] as? String }
        )
    }

    @Test("console.log renders a row rather than refusing the engine's own reads")
    func aRowPrints() throws {
        let run = try run("console.log(doc.tree('Cnv01')[0])")

        #expect(run.error == nil)
        guard case let .log(_, text) = run.events.first else {
            Issue.record("nothing was logged: \(run.events)")
            return
        }
        #expect(text.contains("\"id\":\"Cnv01\""))
    }

    @Test("spreading a row and reading its keys behave, and the copy is a plain object")
    func aRowSpreads() throws {
        let run = try run(
            """
            const row = doc.tree('Cnv01')[0];
            ({ keys: Object.keys(row).includes('address'), id: ({ ...row }).id });
            """
        )

        #expect(run.error == nil)
        #expect(run.result == .dictionary([
            "keys": .bool(true),
            "id": .string("Cnv01"),
        ]))
    }
}
