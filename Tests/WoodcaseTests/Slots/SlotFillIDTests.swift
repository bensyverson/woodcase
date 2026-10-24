//
//  SlotFillIDTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Ids inside fills stay unique across paste, duplicate and replace (Penumbra spec §13.5
/// rule 8): Pen renames a repeated id on load, a node in a fill included
/// (`project/2026-09-26-slot-override-keys.md`, rule 6), and a path to the repeat stops
/// resolving.
@MainActor
struct SlotFillIDTests {
    /// Every id in the document, the nodes in every fill included, with repeats.
    private func everyID(in doc: EditableDocument) -> [String] {
        var ids = Array(doc.nodes.keys)
        for node in doc.nodes.values {
            guard case let .ref(data) = node.kind else { continue }
            for entry in (data.descendants ?? [:]).values {
                guard case let .array(fill)? = entry.properties["children"] else { continue }
                ids += SlotJSON.allIDs(in: fill)
            }
        }
        return ids
    }

    private func repeats(in doc: EditableDocument) -> Set<String> {
        var seen: Set<String> = []
        var repeated: Set<String> = []
        for id in everyID(in: doc) where !seen.insert(id).inserted {
            repeated.insert(id)
        }
        return repeated
    }

    @Test("Duplicating a filled instance gives its fill fresh ids")
    func duplicateStoredInstance() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(repeats(in: doc).isEmpty)
        let copy = try #require(plan.placedIDs.first?.split(separator: "/").first.map(String.init))
        #expect(SlotScreenFixture.fillIDs("List", of: copy, in: doc)?.count == 3)
        #expect(doc.slot("\(copy)/List")?.layerCount == 3)
    }

    @Test("Duplicating a filled instance inside a fill renumbers its own fill too")
    func duplicateInstanceInAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["HostInst/Nest/Screen"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(repeats(in: doc).isEmpty)
        #expect(doc.slot("HostInst/Body")?.layerCount == 2)
    }

    @Test("woodcase cp of a filled instance gives its fill fresh ids")
    func copyCommand() throws {
        let doc = try SlotScreenFixture.document()

        _ = try BatchApplier.applyOne(
            .cp(BatchOperation.CopyOp(source: #require(NodeAddress("Filled")), parent: NodeAddress("Board"))),
            to: doc
        )

        #expect(repeats(in: doc).isEmpty)
    }

    @Test("Inserting an instance whose fill repeats ids renumbers the fill")
    func insertRepeatingFill() throws {
        let doc = try SlotScreenFixture.document()
        let source = try doc.materializeSubtree(rootID: "Filled")
        let copy = PenNode(id: "Copy", common: source.common, kind: source.kind)

        let plan = try EditPlanner.planInsert([copy], into: "Board", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(repeats(in: doc).isEmpty)
        #expect(plan.placedIDs == ["Copy/Screen"])
    }

    @Test("Pasting a filled instance gives its fill fresh ids")
    func pasteFilledInstance() throws {
        let doc = try SlotScreenFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["Filled"], from: doc, documentID: "doc")

        let plan = try clip.plan(into: doc, at: .inside(containerID: "Board"))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(repeats(in: doc).isEmpty)
        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(doc.slot("\(pasted)/List")?.layerCount == 3)
    }

    @Test("A carried connector naming a node in a pasted fill follows the renumbered node")
    func pasteConnectorIntoAFill() throws {
        let doc = try SlotScreenFixture.document()
        let connector = try PenParser.parse(Data("""
        {"version": "2.19", "children": [{"type": "connection", "id": "K1",
          "source": {"path": "Filled/Row2", "anchor": "right"}, "target": {"path": "Loose", "anchor": "left"}}]}
        """.utf8)).children[0]
        try doc.apply(.insertNode(EditOperation.InsertNode(node: connector)))
        let clip = try PenClip.extract(nodeIDs: ["Filled", "Board"], from: doc, documentID: "doc")

        let plan = try clip.plan(into: doc, at: .inPlace)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(repeats(in: doc).isEmpty)
        let pasted = doc.nodes.values.compactMap { node -> String? in
            guard node.id != "K1", case let .connection(data) = node.kind else { return nil }
            return data.source.path
        }
        let path = try #require(pasted.first)
        #expect(path != "Filled/Row2")
        #expect(try doc.resolve(#require(NodeAddress(path.split(separator: "/").map { "#\($0)" }.joined(separator: "/")))) != nil)
    }
}
