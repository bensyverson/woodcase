//
//  RowPredicateTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// ``RowPredicate`` — the JavaScript filter behind `woodcase find`.
///
/// The subject is the contract the verb rests on: which rows come back, and what a
/// reader is told when the predicate is wrong. A predicate is the smallest possible
/// script — one expression, no `doc`, no writes — so every failure here has to teach
/// with the sentence alone.
@Suite("row predicates")
struct RowPredicateTests {
    /// The rows of `batch.pen`, settled, with no property columns.
    private func rows(properties: [String] = []) throws -> [TreeRow] {
        let document = try ScriptFixture.document("batch.pen")
        return try TreeView.rows(of: document, properties: properties)
    }

    /// Runs a predicate over `batch.pen`'s rows.
    private func match(
        _ predicate: String,
        properties: [String] = []
    ) throws -> RowPredicate.Outcome {
        try RowPredicate.match(
            rows(properties: properties),
            where: .text(predicate, name: "<argv>"),
            properties: properties
        )
    }

    // MARK: - Matching

    @Test("a predicate keeps the rows it answers truthy for, in tree order")
    func keepsTruthyRows() throws {
        let outcome = try match("r => r.type === 'text'")

        #expect(outcome.error == nil)
        #expect(outcome.rows.map(\.id) == ["Ttl01", "Lbl01"])
    }

    @Test("a predicate that answers for nothing comes back empty, and is not an error")
    func emptyIsNotAnError() throws {
        let outcome = try match("r => r.type === 'ellipse'")

        #expect(outcome.rows.isEmpty)
        #expect(outcome.error == nil)
        #expect(outcome.failingRow == nil)
    }

    @Test("truthiness, not equality: any truthy answer keeps the row")
    func truthinessKeepsTheRow() throws {
        let outcome = try match("r => r.childCount")

        #expect(outcome.error == nil)
        #expect(outcome.rows.allSatisfy { $0.childCount > 0 })
        #expect(!outcome.rows.isEmpty)
    }

    @Test("a member that is legitimately absent on this row reads as undefined, not a throw")
    func absentOptionalMemberIsUndefined() throws {
        // `name` is a member every row may carry and this document's rows all do; the
        // point is that reading it never refuses, whatever the row holds.
        let every = try rows()
        let outcome = try match("r => r.name === undefined || typeof r.name === 'string'")

        #expect(outcome.error == nil)
        #expect(outcome.rows.count == every.count)
    }

    // MARK: - The property columns

    @Test("r.props reads a column --props asked for")
    func propsReadsARequestedColumn() throws {
        let outcome = try match(
            "r => r.props['kind.content'] === 'Canvas'",
            properties: ["kind.content"]
        )

        #expect(outcome.error == nil)
        #expect(outcome.rows.map(\.id) == ["Ttl01"])
    }

    @Test("r.props with no --props refuses, naming the flag that would fill it")
    func propsWithoutColumnsRefuses() throws {
        let outcome = try match("r => r.props['kind.fontSize'] < 12")

        let error = try #require(outcome.error)
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("--props"))
        #expect(error.message.contains("kind.fontSize"))
    }

    @Test("a property path outside the requested columns refuses, listing the ones asked for")
    func unrequestedPathRefuses() throws {
        let outcome = try match(
            "r => r.props['kind.fontSize'] < 12",
            properties: ["kind.content"]
        )

        let error = try #require(outcome.error)
        #expect(error.message.contains("kind.content"))
        #expect(error.code == ScriptErrorCode.unknownMember)
    }

    @Test("r.properties — the row's own key — reads the same guarded view as r.props")
    func propertiesIsTheSameView() throws {
        let kept = try match(
            "r => r.properties['kind.content'] === 'Canvas'",
            properties: ["kind.content"]
        )
        #expect(kept.error == nil)
        #expect(kept.rows.map(\.id) == ["Ttl01"])

        // The point of one view behind two spellings: the second cannot be the hole the
        // first closed.
        let refused = try match(
            "r => r.properties['kind.fontSize'] < 12",
            properties: ["kind.content"]
        )
        #expect(refused.error?.code == ScriptErrorCode.unknownMember)
        #expect(refused.error?.message.contains("r.properties") == true)
    }

    @Test("a requested path a row does not carry is undefined, not a refusal")
    func requestedPathAbsentOnARowIsUndefined() throws {
        let outcome = try match(
            "r => r.props['kind.content'] === undefined",
            properties: ["kind.content"]
        )

        #expect(outcome.error == nil)
        #expect(!outcome.rows.isEmpty)
    }

    // MARK: - The mistakes to expect

    @Test("a property outside r.props refuses, listing the members a row carries")
    func unknownMemberListsTheMembers() throws {
        let outcome = try match("r => r.fontSize < 12")

        let error = try #require(outcome.error)
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("fontSize"))
        for member in ["type", "address", "rect", "absRect", "depth", "childCount"] {
            #expect(error.message.contains(member), "the sentence should list \(member)")
        }
        #expect(error.message.contains("r.props"))
    }

    @Test("the refusal names the row it happened on")
    func unknownMemberNamesTheRow() throws {
        let outcome = try match("r => r.fontSize < 12")

        let row = try #require(outcome.failingRow)
        #expect(row.id == "Cnv01")
    }

    @Test("undefined < 12 would be silently false, so the member is refused instead")
    func theSilentComparisonIsRefused() throws {
        // The whole reason the row is a Proxy: `r.fontSize` is `undefined`, and
        // `undefined < 12` is `false` without throwing, so a plain object would answer
        // "no rows" to a question that was never asked.
        let outcome = try match("r => r.fontSize < 12")

        #expect(outcome.rows.isEmpty)
        #expect(outcome.error != nil)
    }

    @Test("a predicate cannot reach doc, and is told where doc lives")
    func docIsOutOfReach() throws {
        let outcome = try match("r => doc")

        let error = try #require(outcome.error)
        #expect(error.message.contains("doc"))
        #expect(error.message.contains("js"))
        #expect(error.message.lowercased().contains("read"))
    }

    @Test("a predicate that does not parse reports the parser's line and message")
    func syntaxErrorCarriesLineAndMessage() throws {
        let outcome = try match("r => (")

        let error = try #require(outcome.error)
        #expect(error.code == ScriptErrorCode.syntaxError)
        #expect(error.line == 1)
        #expect(!error.message.isEmpty)
        #expect(outcome.failingRow == nil)
    }

    @Test("a predicate that is not a function at all says what one looks like")
    func aNonFunctionIsRefused() throws {
        let outcome = try match("'kind.fontSize'")

        let error = try #require(outcome.error)
        #expect(error.message.contains("r =>"))
        #expect(error.message.contains("string"))
    }

    @Test("a throw from the predicate's own code keeps its message and its line")
    func aThrowKeepsItsMessage() throws {
        let outcome = try match("r => { throw new Error('nope') }")

        let error = try #require(outcome.error)
        #expect(error.message.contains("nope"))
        #expect(error.line == 1)
        #expect(outcome.failingRow?.id == "Cnv01")
    }

    // MARK: - Drift

    @Test("the member list is the row type's own keys, so it cannot drift")
    func theMemberListIsTheRowsOwnKeys() throws {
        let row = try #require(rows().first)
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONSerialization.jsonObject(with: data)
        let object = try #require(decoded as? [String: Any])

        for key in object.keys {
            #expect(
                RowViewPrelude.memberNames.contains(key),
                "a row carries \(key) but the predicate would refuse it"
            )
        }
    }
}
