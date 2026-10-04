//
//  ChangeWalkPruningTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How much of a document the two-way change walk visits: equal revisions prune whole subtrees.
@MainActor
struct ChangeWalkPruningTests {
    /// Nodes in the synthetic document: one 1,601-node artboard of 400 rows and a truncated second.
    private static let nodeCount = 2000

    /// Two independently built copies of the same synthetic document.
    private func pair() throws -> (from: EditableDocument, to: EditableDocument) {
        let bytes = try PenParser.encodeForFile(SyntheticPenDocument.make(nodeCount: Self.nodeCount))
        return try (EditableDocument(from: PenParser.parse(bytes)), EditableDocument(from: PenParser.parse(bytes)))
    }

    @Test("Two identical ~2,000-node documents visit only the roots")
    func identicalVisitsRoots() throws {
        let (from, to) = try pair()
        #expect(from.rootOrder.count == 2)
        var walk = ChangeWalk(from: from, to: to)
        let changes = walk.run()
        #expect(changes.isEmpty)
        #expect(walk.visits == from.rootOrder.count)
    }

    @Test("A one-leaf edit visits only its spine and the siblings along it")
    func oneLeafVisitsSpine() throws {
        let (from, to) = try pair()
        // n00001 is the first artboard, n00002 its first row, n00003 that row's first text.
        try to.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "n00003", properties: ["common.name": .string("Edited")]
        )))
        var walk = ChangeWalk(from: from, to: to)
        let changes = walk.run()

        let roots = from.rootOrder.count
        let rows = try #require(from.children["n00001"]).count
        let texts = try #require(from.children["n00002"]).count
        #expect(walk.visits == roots + rows + texts)
        #expect(Set(changes.nodes.keys) == ["n00003"])
        #expect(changes.nodes["n00003"]?.keys == [.property("common.name")])
    }

    @Test("A move between artboards visits both spines and reports the move")
    func moveVisitsBothSpines() throws {
        let (from, to) = try pair()
        let secondArtboard = from.rootOrder[1]
        try to.apply(.moveNode(EditOperation.MoveNode(nodeID: "n00003", newParentID: secondArtboard, index: 0)))
        var walk = ChangeWalk(from: from, to: to)
        let changes = walk.run()

        #expect(changes.nodes["n00003"]?.keys == [.parent])
        #expect(changes.nodes["n00002"]?.keys == [.children])
        #expect(changes.nodes[secondArtboard]?.keys == [.children])
        let roots = from.rootOrder.count
        let rows = try #require(from.children["n00001"]).count
        let texts = try #require(from.children["n00002"]).count
        // The moved leaf is reached from both parents but visited once, so count the
        // second artboard's rows without it.
        let secondRows = try #require(from.children[secondArtboard]).count
        #expect(walk.visits == roots + rows + texts + secondRows)
    }
}
