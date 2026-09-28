//
//  TreeViewCircularRefTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An expanded tree read stops at a circular `ref` exactly where the expansion does.
///
/// ``PenRefExpander`` leaves a `ref` as written when the component it names is already
/// on the expansion chain — its own instance inside itself, two components placing each
/// other, a slot filled with the component that holds the slot. The tree walk has to
/// stop at the same ref: walking on lists rows the expansion never made, and never ends.
/// A `moveNode` that puts an instance inside its own component writes such a document,
/// which is how `IncrementalSettleEquivalenceTests` once ran for minutes.
///
/// Each read is depth-limited, so a walk that does not stop fails here rather than
/// hanging the suite.
@MainActor
struct TreeViewCircularRefTests {
    /// Deeper than any row these documents legitimately have.
    private static let depthLimit = 12

    private func rows(_ json: String) throws -> (rows: [TreeRow], settled: SettledTree) {
        let document = try EditableDocument(from: PenParser.parse(Data(json.utf8)))
        let settled = SettledTree(document: document, theme: [:])
        let rows = try TreeView.rows(
            of: document, settled: settled, depth: Self.depthLimit, expandInstances: true
        )
        return (rows, settled)
    }

    /// The row is the circular ref as the expansion left it: a ref, with nothing below.
    ///
    /// - Parameter settledID: The id the expansion's node has, when it is not the row's —
    ///   an alias whose target is on the chain is cloned whole, a `ref` under its own id.
    private func expectLeafRef(
        _ id: String, settledAs settledID: String? = nil, in rows: [TreeRow], settled: SettledTree
    ) throws {
        let row = try #require(rows.first { $0.id == id }, "no row \(id)")
        #expect(row.type == "ref", "\(id) is a \(row.type)")
        #expect(row.childCount == 0, "\(id) has \(row.childCount) children")
        let expandedID = settledID ?? id
        let node = try #require(settled.nodes[expandedID], "the expansion has no node \(expandedID)")
        guard case .ref = node.kind else {
            Issue.record("the expansion expanded \(expandedID)")
            return
        }
    }

    @Test("An instance of a component inside that component is one row, like the expansion's")
    func selfPlacingComponent() throws {
        let (rows, settled) = try rows("""
        {"version": "2.17", "children": [
          {"id": "CmpA0", "type": "frame", "reusable": true, "width": 100, "height": 100,
           "children": [{"id": "Self0", "type": "ref", "ref": "CmpA0"}]},
          {"id": "Inst0", "type": "ref", "ref": "CmpA0", "x": 200}
        ]}
        """)

        #expect(rows.map(\.id) == ["CmpA0", "Self0", "Self0/Self0", "Inst0", "Inst0/Self0"])
        try expectLeafRef("Self0/Self0", in: rows, settled: settled)
        try expectLeafRef("Inst0/Self0", in: rows, settled: settled)
    }

    @Test("Two components placing each other stop where the chain comes back round")
    func mutuallyPlacingComponents() throws {
        let (rows, settled) = try rows("""
        {"version": "2.17", "children": [
          {"id": "CmpA0", "type": "frame", "reusable": true, "width": 100, "height": 100,
           "children": [{"id": "ToB00", "type": "ref", "ref": "CmpB0"}]},
          {"id": "CmpB0", "type": "frame", "reusable": true, "width": 100, "height": 100, "x": 200,
           "children": [{"id": "ToA00", "type": "ref", "ref": "CmpA0"}]},
          {"id": "Inst0", "type": "ref", "ref": "CmpA0", "x": 400}
        ]}
        """)

        #expect(rows.map(\.id) == [
            "CmpA0", "ToB00", "ToB00/ToA00", "ToB00/ToA00/ToB00",
            "CmpB0", "ToA00", "ToA00/ToB00", "ToA00/ToB00/ToA00",
            "Inst0", "Inst0/ToB00", "Inst0/ToB00/ToA00",
        ])
        try expectLeafRef("ToB00/ToA00/ToB00", in: rows, settled: settled)
        try expectLeafRef("Inst0/ToB00/ToA00", in: rows, settled: settled)
    }

    @Test("A component reached through an alias is on the chain under both names")
    func cycleThroughAnAlias() throws {
        let (rows, settled) = try rows("""
        {"version": "2.17", "children": [
          {"id": "CmpA0", "type": "frame", "reusable": true, "width": 100, "height": 100,
           "children": [{"id": "ToAl0", "type": "ref", "ref": "Alias"}]},
          {"id": "Alias", "type": "ref", "reusable": true, "ref": "CmpA0", "x": 200},
          {"id": "Inst0", "type": "ref", "ref": "CmpA0", "x": 400}
        ]}
        """)

        try expectLeafRef("ToAl0/ToAl0", in: rows, settled: settled)
        // Inside `Inst0` the chain already holds `CmpA0`, so the alias stops at itself.
        try expectLeafRef("Inst0/ToAl0", settledAs: "Inst0/ToAl0/Alias", in: rows, settled: settled)
        #expect(rows.map(\.depth).max() ?? 0 < 3)
    }

    @Test("A slot filled with the component that holds it expands no further")
    func slotFilledWithItsOwnComponent() throws {
        let (rows, settled) = try rows("""
        {"version": "2.17", "children": [
          {"id": "Card0", "type": "frame", "reusable": true, "width": 100, "height": 100,
           "children": [{"id": "Slot0", "type": "frame", "slot": ["ref"], "width": 80, "height": 80}]},
          {"id": "Inst0", "type": "ref", "ref": "Card0", "x": 200,
           "descendants": {"Slot0": {"children": [{"id": "Back0", "type": "ref", "ref": "Card0"}]}}}
        ]}
        """)

        #expect(rows.map(\.id) == ["Card0", "Slot0", "Inst0", "Inst0/Slot0", "Inst0/Back0"])
        try expectLeafRef("Inst0/Back0", in: rows, settled: settled)
    }
}
