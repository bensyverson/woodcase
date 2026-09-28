//
//  BatchOperationCodableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct BatchOperationCodableTests {
    /// One line per op kind, in the grammar's own spelling.
    private static let everyKind = """
    {"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"},"rev":"9f3a0000abcd1234"}
    {"op":"add","parent":"Cards","node":{"id":"New01","type":"frame","name":"Hero","width":10},"at":2,"tag":"hero"}
    {"op":"replace","target":"Cards","node":{"id":"Crd01","type":"frame","name":"Cards"},"rev":"9f3a0000abcd1234"}
    {"op":"cp","source":"Cards/First","parent":"Cards","at":0,"tag":"clone","props":{"common.name":"Third"}}
    {"op":"mv","target":"Cards/First","parent":"Board","at":1}
    {"op":"rm","target":"Cards/Second","detach":true}
    {"op":"override","target":"Board/Chip/Label","props":{"content":"Menu"}}
    {"op":"var","name":"brand","value":{"type":"color","value":"#ff0000"}}
    {"op":"theme-axis","name":"mode","options":["light","dark"]}
    {"op":"import","alias":"V","path":"./library.pen"}
    """

    // MARK: - Round trip

    @Test("Every op kind decodes from JSONL and re-encodes to the same value")
    func roundTripEveryKind() throws {
        let ops = try BatchOperation.decodeJSONL(Self.everyKind)
        #expect(ops.count == BatchOperation.Verb.allCases.count)
        let again = try BatchOperation.decodeJSONL(BatchOperation.encodeJSONL(ops))
        #expect(again == ops)
    }

    @Test("Each line decodes to the verb it names")
    func verbs() throws {
        let ops = try BatchOperation.decodeJSONL(Self.everyKind)
        #expect(ops.map(\.verb) == [
            .set, .add, .replace, .cp, .mv, .rm, .override, .variable, .themeAxis, .importOp,
        ])
    }

    @Test("Fields decode into the op's own shape")
    func fields() throws {
        let ops = try BatchOperation.decodeJSONL(Self.everyKind)
        guard case let .add(add) = ops[1] else {
            Issue.record("expected an add op")
            return
        }
        #expect(add.parent == NodeAddress("Cards"))
        #expect(add.at == 2)
        #expect(add.tag == "hero")
        #expect(add.node.common.name == "Hero")

        guard case let .rm(remove) = ops[5] else {
            Issue.record("expected an rm op")
            return
        }
        #expect(remove.detach)
        #expect(remove.target == NodeAddress("Cards/Second"))
    }

    // MARK: - Defaults

    @Test("An omitted parent means the document root, and rm defaults to no detach")
    func defaults() throws {
        let ops = try BatchOperation.decodeJSONL("""
        {"op":"add","node":{"id":"Nw001","type":"frame","name":"Loose"}}
        {"op":"rm","target":"Loose"}
        """)
        guard case let .add(add) = ops[0], case let .rm(remove) = ops[1] else {
            Issue.record("expected an add then an rm")
            return
        }
        #expect(add.parent == nil)
        #expect(remove.detach == false)
    }

    @Test("A node written without ids decodes with empty ids, which the insert reads as 'draw me one'")
    func nodeWithoutIDs() throws {
        let ops = try BatchOperation.decodeJSONL("""
        {"op":"add","parent":"Cards","node":{"type":"frame","name":"Hero","children":[\
        {"type":"text","name":"Caption","content":"hi"}]}}
        """)
        guard case let .add(add) = ops[0] else {
            Issue.record("expected an add op")
            return
        }
        #expect(add.node.common.name == "Hero")
        #expect(add.node.id == PenSubtreeDecoder.unsuppliedID)
        guard case let .frame(frame) = add.node.kind, let child = frame.children?.first else {
            Issue.record("expected one inline child")
            return
        }
        #expect(child.common.name == "Caption")
        #expect(child.id == PenSubtreeDecoder.unsuppliedID)
    }

    @Test("An id written in the subtree survives decoding, because the insert will keep it")
    func nodeWithSuppliedIDs() throws {
        let ops = try BatchOperation.decodeJSONL("""
        {"op":"add","parent":"Cards","node":{"id":"Hero1","type":"frame","name":"Hero","children":[\
        {"type":"text","name":"Caption","content":"hi"}]}}
        """)
        guard case let .add(add) = ops[0] else {
            Issue.record("expected an add op")
            return
        }
        #expect(add.node.id == "Hero1")
    }

    // MARK: - Tags

    @Test("A tag address parses as a tag, and a batch tag is only declared by add and cp")
    func tagAddress() throws {
        let ops = try BatchOperation.decodeJSONL("""
        {"op":"set","target":"@hero","props":{"kind.content":"Hi"}}
        """)
        guard case let .set(set) = ops[0] else {
            Issue.record("expected a set op")
            return
        }
        #expect(set.target == .tag(name: "hero", path: []))
        #expect(ops[0].declaredTag == nil)
    }

    @Test("add and cp report the tag they declare")
    func declaredTag() throws {
        let ops = try BatchOperation.decodeJSONL(Self.everyKind)
        #expect(ops[1].declaredTag == "hero")
        #expect(ops[2].declaredTag == nil, "replace creates nothing to tag")
        #expect(ops[3].declaredTag == "clone")
    }

    @Test("An import line decodes into its alias and path, and re-encodes to the same bytes")
    func importFields() throws {
        let line = #"{"op":"import","alias":"V","path":"./library.pen"}"#
        let ops = try BatchOperation.decodeJSONL(line)
        guard case let .importOp(op) = ops[0] else {
            Issue.record("expected an import op")
            return
        }
        #expect(op.alias == "V")
        #expect(op.path == "./library.pen")
        // `encodeJSONL` sorts keys, so the bytes are alphabetical rather than as written.
        #expect(try BatchOperation.encodeJSONL(ops)
            == #"{"alias":"V","op":"import","path":"./library.pen"}"#)
    }

    @Test("An import line carries a guard, because it acts on no node of its own")
    func importGuard() throws {
        let ops = try BatchOperation.decodeJSONL(
            #"{"op":"import","alias":"V","path":"./library.pen","guard":{"node":"document","rev":"9f3a0000abcd1234"}}"#
        )
        #expect(ops[0].guards.count == 1)
        #expect(ops[0].guardTarget == .nothing)
        #expect(ops[0].rev == nil)
        #expect(ops[0].addresses.isEmpty)
        #expect(ops[0].targetAddress == nil)
        #expect(ops[0].declaredTag == nil)
    }

    // MARK: - Errors

    @Test("An unknown op name is a decoding error naming the verb")
    func unknownVerb() {
        #expect(throws: (any Error).self) {
            try BatchOperation.decodeJSONL(#"{"op":"nope","target":"A"}"#)
        }
    }

    @Test("Blank lines between ops are skipped, so a hand-written file still parses")
    func blankLines() throws {
        let ops = try BatchOperation.decodeJSONL("""
        {"op":"rm","target":"A"}

        {"op":"rm","target":"B"}

        """)
        #expect(ops.count == 2)
    }

    // MARK: - Grammar

    @Test("The grammar names every verb, so help and schema print one source of truth")
    func grammarNamesEveryVerb() {
        for verb in BatchOperation.Verb.allCases {
            #expect(BatchOperation.grammar.contains("\"\(verb.rawValue)\""))
        }
    }
}
