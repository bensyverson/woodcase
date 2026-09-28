//
//  BatchGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The guard seam at the library level: the wire form, what a bare guard pins, and the
/// entry-time check itself.
///
/// `GuardCommandTests` drives the same thing through the binary, where the exit code and
/// the sentence are the subject. Here the subject is the contract those rest on.
@MainActor
struct BatchGuardTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document() throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: "addressing", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("addressing.pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func set(_ address: String, _ text: String, guards: [BatchGuard] = []) -> BatchOperation {
        .set(BatchOperation.SetOp(
            target: NodeAddress(address) ?? .path([address]),
            props: ["kind.content": .string(text)],
            guards: guards
        ))
    }

    // MARK: - The wire form

    @Test("A guard is written as a bare revision, as an object, or as a list of either")
    func guardsRoundTrip() throws {
        let lines = """
        {"op":"set","target":"Title","props":{"kind.content":"a"},"guard":"9f3a0000abcd1234"}
        {"op":"set","target":"Title","props":{"kind.content":"b"},"guard":{"node":"Dashboard","rev":"9f3a0000abcd1234"}}
        {"op":"add","parent":"Header","node":{"type":"text","name":"X"},"guard":{"node":"document","rev":"9f3a0000abcd1234"}}
        {"op":"rm","target":"Title","guard":["9f3a0000abcd1234",{"node":"Body","rev":"0000000000000000"}]}
        """

        let ops = try BatchOperation.decodeJSONL(lines)
        let dashboard = try #require(NodeAddress("Dashboard"))
        let reencoded = try BatchOperation.decodeJSONL(BatchOperation.encodeJSONL(ops))

        #expect(ops[0].guards == [BatchGuard(rev: "9f3a0000abcd1234")])
        #expect(ops[1].guards == [BatchGuard(rev: "9f3a0000abcd1234", scope: .node(dashboard))])
        #expect(ops[2].guards == [BatchGuard(rev: "9f3a0000abcd1234", scope: .document)])
        #expect(ops[3].guards.count == 2)
        #expect(reencoded == ops)
    }

    @Test("A line with no guard field carries no guards, and re-encodes without one")
    func unguardedLinesStayUnguarded() throws {
        let line = #"{"op":"set","target":"Title","props":{"kind.content":"a"}}"#
        let ops = try BatchOperation.decodeJSONL(line)

        let encoded = try BatchOperation.encodeJSONL(ops)
        #expect(ops[0].guards.isEmpty)
        #expect(!encoded.contains("guard"))
    }

    // MARK: - What a bare guard pins

    @Test("A bare guard pins the target, the parent, or the document, exactly as rev does")
    func bareGuardsPinTheSameNodeRevDoes() throws {
        let set = set("Header/Title", "a")
        let addToParent = BatchOperation.add(BatchOperation.AddOp(
            node: PenNode(id: "N", common: PenNodeCommon(name: "N"), kind: .text(PenNode.TextData())),
            parent: NodeAddress("Header")
        ))
        let addToRoot = BatchOperation.add(BatchOperation.AddOp(
            node: PenNode(id: "N", common: PenNodeCommon(name: "N"), kind: .text(PenNode.TextData()))
        ))
        let variable = BatchOperation.variable(BatchOperation.VariableOp(
            name: "brand", value: PenVariable(type: .color, value: .simple(.string("#fff")))
        ))

        let title = try #require(NodeAddress("Header/Title"))
        let header = try #require(NodeAddress("Header"))
        #expect(set.guardTarget == .node(title))
        #expect(addToParent.guardTarget == .node(header))
        #expect(addToRoot.guardTarget == .document)
        #expect(variable.guardTarget == .nothing)
    }

    // MARK: - The entry check

    @Test("A guard quoting the current revision passes, and one quoting anything else does not")
    func aGuardComparesAgainstTheDocument() throws {
        let document = try document()
        let current = try #require(document.revision(of: "Ttl01"))

        try BatchApplier.checkGuards([set("Header/Title", "a", guards: [BatchGuard(rev: current)])], in: document)

        #expect(throws: BatchError.self) {
            try BatchApplier.checkGuards(
                [set("Header/Title", "a", guards: [BatchGuard(rev: "0000000000000000")])], in: document
            )
        }
    }

    @Test("An ancestor guard is checked against that ancestor, not against the target")
    func anAncestorGuardIsCheckedThere() throws {
        let document = try document()
        let header = try #require(document.revision(of: "Hdr01"))
        let address = try #require(NodeAddress("Header"))
        let pin = BatchGuard(rev: header, scope: .node(address))

        try BatchApplier.checkGuards([set("Header/Title", "a", guards: [pin])], in: document)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Unn01", properties: ["kind.content": .string("moved")]
        )))
        #expect(throws: BatchError.self) {
            try BatchApplier.checkGuards([set("Header/Title", "a", guards: [pin])], in: document)
        }
    }

    @Test("A document guard is checked against the document revision")
    func aDocumentGuardIsCheckedAgainstTheDocument() throws {
        let document = try document()
        let pin = BatchGuard(rev: document.documentRevision, scope: .document)

        try BatchApplier.checkGuards([set("Header/Title", "a", guards: [pin])], in: document)

        try document.apply(.addVariable(EditOperation.AddVariable(
            name: "spacing", variable: PenVariable(type: .number, value: .simple(.int(4)))
        )))
        #expect(throws: BatchError.self) {
            try BatchApplier.checkGuards([set("Header/Title", "a", guards: [pin])], in: document)
        }
    }

    @Test("A bare guard on a line that acts on no node is refused, naming the verb")
    func aBareGuardOnADocumentLineIsRefused() throws {
        let document = try document()
        let variable = BatchOperation.variable(BatchOperation.VariableOp(
            name: "brand",
            value: PenVariable(type: .color, value: .simple(.string("#fff"))),
            guards: [BatchGuard(rev: "0000000000000000")]
        ))

        #expect(throws: BatchError.guardWithoutTarget(verb: "var")) {
            try BatchApplier.checkGuards([variable], in: document)
        }
    }

    @Test("A variable line may still guard a node it names")
    func aScopedGuardOnADocumentLineWorks() throws {
        let document = try document()
        let header = try #require(document.revision(of: "Hdr01"))
        let address = try #require(NodeAddress("Header"))
        let variable = BatchOperation.variable(BatchOperation.VariableOp(
            name: "brand",
            value: PenVariable(type: .color, value: .simple(.string("#fff"))),
            guards: [BatchGuard(rev: header, scope: .node(address))]
        ))

        try BatchApplier.checkGuards([variable], in: document)
    }

    @Test("Nothing is checked for a line with no guards, whatever the document says")
    func unguardedLinesAreNeverChecked() throws {
        let document = try document()
        try BatchApplier.checkGuards([set("Header/Title", "a")], in: document)
    }

    // MARK: - Coverage

    @Test("A node's revision coverage is its subtree plus everything its instances render")
    func coverageFollowsTheRefGraph() throws {
        let document = try document()

        let body = document.revisionCoverage(of: "Body1")

        // The subtree the file stores under Body1 …
        #expect(body.isSuperset(of: ["Body1", "Ttl02", "Nav01"]))
        // … and the component Nav01 draws, and the one nested inside that.
        #expect(body.isSuperset(of: ["Btn01", "Lbl01", "Bdg01", "Bge01", "Cnt01"]))
        // Not the header branch, which Body1 neither holds nor draws.
        #expect(!body.contains("Hdr01"))
    }
}
