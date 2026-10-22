//
//  PropertyApplicationOrderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A set-properties op whose keys share storage gives one node however its dictionary
/// iterates (leaf zZTmAg): its keys apply broadest storage first, ties by path, so
/// `common.metadata` lands before `note.fontSize` refines it. Each case is built in every
/// iteration order a dictionary of its entries can take, and each is checked to overlap —
/// the two orders written key by key give different nodes — so agreement is not luck.
@MainActor
struct PropertyApplicationOrderTests {
    typealias Outcome = PropertyWriteOracleTests.Outcome

    /// One op's entries, on one node, and the order its keys must land in.
    struct Case {
        let name: String
        let nodeID: String
        let entries: [(String, AnyCodable)]
        /// The keys, broadest storage first.
        let canonical: [String]
    }

    static let metadata: AnyCodable = .dictionary([
        "type": .string("woodcase"),
        "woodcase": .dictionary(["fontSize": .int(30), "role": .string("button"), "tint": .string("#FFFFFF")]),
    ])

    static let namedSpread: AnyCodable = .array([.dictionary([
        "type": .string("shadow"), "shadowType": .string("outer"), "blur": .int(4), "spread": .int(3),
        "color": .string("#00000040"),
    ])])

    static let cases: [Case] = [
        Case(
            name: "a note alias beside its raw metadata", nodeID: "n",
            entries: [("note.fontSize", .int(20)), ("common.metadata", metadata)],
            canonical: ["common.metadata", "note.fontSize"]
        ),
        Case(
            name: "a codegen path beside metadata", nodeID: "c",
            entries: [("codegen.role", .string("link")), ("common.metadata", metadata)],
            canonical: ["common.metadata", "codegen.role"]
        ),
        Case(
            name: "a natural common path beside metadata", nodeID: "c",
            entries: [("common.locked", .bool(true)), ("common.metadata", metadata)],
            canonical: ["common.metadata", "common.locked"]
        ),
        Case(
            name: "a named spread beside metadata", nodeID: "c",
            entries: [("kind.effects", namedSpread), ("common.metadata", metadata)],
            canonical: ["common.metadata", "kind.effects"]
        ),
        Case(
            name: "a deep codegen key beside its parent", nodeID: "c",
            entries: [("codegen.props.label", .string("Box")), ("codegen.props", .dictionary(["tint": .string("Box")]))],
            canonical: ["codegen.props", "codegen.props.label"]
        ),
    ]

    static func node(_ id: String) -> PenNode {
        id == "n"
            ? PenNode(id: "n", common: PenNodeCommon(x: .literal(1)), kind: .note(PenNode.NoteData(content: .literal("Hi"))))
            : PenNode(id: "c", common: PenNodeCommon(name: "Card"), kind: .frame(PenNode.FrameData(width: .fixed(100))))
    }

    static func penDocument() -> PenDocument {
        PenDocument(children: [node("n"), node("c")])
    }

    /// The keys written one at a time, in the order given.
    static func perKey(_ entries: [(String, AnyCodable)], order: [String], on node: PenNode) throws -> PenNode {
        let values = Dictionary(uniqueKeysWithValues: entries)
        return try order.reduce(node) { try NodePropertyCodec.setting(values[$1]!, at: $1, on: $0) }
    }

    /// The case's dictionaries — at least two iteration orders, or the case proves nothing.
    static func variants(of testCase: Case) throws -> [[String: AnyCodable]] {
        let maps = DictionaryOrderings.distinct(testCase.entries)
        let orders = Set(maps.map { Array($0.keys) })
        try #require(orders.count == maps.count && orders.count >= 2, "\(testCase.name): \(orders)")
        return maps
    }

    @Test("Each case's keys overlap: written key by key, the two orders give different nodes")
    func casesOverlap() throws {
        for testCase in Self.cases {
            let node = Self.node(testCase.nodeID)
            let forward = try Self.perKey(testCase.entries, order: testCase.canonical, on: node)
            let backward = try Self.perKey(testCase.entries, order: testCase.canonical.reversed(), on: node)
            #expect(forward != backward, "\(testCase.name)")
        }
    }

    @Test("An op's ordered properties put broadest storage first, ties by path, in every iteration order")
    func orderedProperties() throws {
        for testCase in Self.cases {
            for map in try Self.variants(of: testCase) {
                let op = EditOperation.SetProperties(nodeID: testCase.nodeID, properties: map)
                #expect(op.orderedProperties.map(\.key) == testCase.canonical, "\(testCase.name)")
            }
        }
        let mixed = EditOperation.SetProperties(nodeID: "c", properties: [
            "kind.width": .int(1), "common.name": .string("B"), "codegen.props.label": .string("L"),
            "common.metadata": Self.metadata, "codegen.role": .string("link"),
        ])
        #expect(mixed.orderedProperties.map(\.key) == [
            "common.metadata", "common.name", "kind.width", "codegen.role", "codegen.props.label",
        ])
    }

    @Test("The codec's batch write lands broadest storage first in every iteration order")
    func codecBatch() throws {
        for testCase in Self.cases {
            let node = Self.node(testCase.nodeID)
            let expected = try Self.perKey(testCase.entries, order: testCase.canonical, on: node)
            for map in try Self.variants(of: testCase) {
                #expect(try NodePropertyCodec.setting(map, on: node) == expected, "\(testCase.name) \(Array(map.keys))")
            }
        }
    }

    @Test("A refusal names the same key in every iteration order: the first in canonical order")
    func refusalIsCanonical() throws {
        let card = Self.node("c")
        let entries: [(String, AnyCodable)] = [("kind.width", .string("wide")), ("common.x", .string("left"))]
        let maps = DictionaryOrderings.distinct(entries)
        try #require(maps.count == 2)
        let expected = Outcome { try NodePropertyCodec.setting(.string("left"), at: "common.x", on: card) }
        for map in maps {
            #expect(Outcome { try NodePropertyCodec.setting(map, on: card) } == expected, "\(Array(map.keys))")
        }
    }

    @Test("The document's patch and its apply give one node in every iteration order")
    func documentApply() throws {
        for testCase in Self.cases {
            let expected = try Self.perKey(testCase.entries, order: testCase.canonical, on: Self.node(testCase.nodeID))
            for map in try Self.variants(of: testCase) {
                let op = EditOperation.SetProperties(nodeID: testCase.nodeID, properties: map)
                let document = EditableDocument(from: Self.penDocument())
                #expect(try document.patchedNode(for: op).new == expected, "\(testCase.name) \(Array(map.keys))")
                try document.apply(.setProperties(op))
                #expect(document.nodes[testCase.nodeID] == expected, "\(testCase.name) \(Array(map.keys))")
            }
        }
    }

    @Test("Two replicas applying the op locally and remotely converge on one node in every iteration order")
    func crdtConverges() throws {
        for testCase in Self.cases {
            let expected = try Self.perKey(testCase.entries, order: testCase.canonical, on: Self.node(testCase.nodeID))
            for map in try Self.variants(of: testCase) {
                let local = EditableDocument(from: Self.penDocument(), peerID: PeerID(rawValue: "aaa"))
                let remote = EditableDocument(from: Self.penDocument(), peerID: PeerID(rawValue: "bbb"))
                let ops = try local.applyLocal(.setProperties(EditOperation.SetProperties(
                    nodeID: testCase.nodeID, properties: map
                )))
                remote.applyRemote(ops)
                let label = "\(testCase.name) \(Array(map.keys))"
                #expect(local.nodes[testCase.nodeID] == expected, "\(label) local")
                #expect(remote.nodes[testCase.nodeID] == expected, "\(label) remote")
            }
        }
    }

    @Test("The CRDT emits an op's writes in one order, whatever order its dictionary iterates")
    func crdtEmissionOrder() throws {
        let entries: [(String, AnyCodable)] = [("common.name", .string("B")), ("kind.width", .int(50))]
        let maps = DictionaryOrderings.distinct(entries)
        try #require(maps.count == 2)
        let emitted = try maps.map { map in
            let document = EditableDocument(from: Self.penDocument(), peerID: PeerID(rawValue: "aaa"))
            let ops = try document.applyLocal(.setProperties(EditOperation.SetProperties(nodeID: "c", properties: map)))
            return ops.compactMap { op -> String? in
                if case let .setProperty(write) = op.payload { return write.property }
                return nil
            }
        }
        #expect(emitted == [["common.name", "kind.width"], ["common.name", "kind.width"]])
    }
}
