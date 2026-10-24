//
//  SlotPasteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A paste into an instance's slot: ``PasteTarget/inside(containerID:)`` naming a slot or a
/// container in its content, and ``PasteTarget/after(siblingID:)`` naming slot content,
/// each written as one `children` override of the slot (Penumbra spec §13.5 rules 4–6,
/// §16 ruling 3).
@MainActor
struct SlotPasteTests {
    /// The slot fixture with `Loose2` beside `Loose` in `Board`, and `KL` from one to the
    /// other.
    private func document() throws -> EditableDocument {
        let doc = try SlotScreenFixture.document()
        let added = try PenParser.parse(Data("""
        {"version": "2.19", "children": [
          {"id": "Loose2", "type": "rectangle", "name": "Loose 2", "x": 100, "y": 10, "width": 30, "height": 20},
          {"type": "connection", "id": "KL", "source": {"path": "Loose", "anchor": "right"},
           "target": {"path": "Loose2", "anchor": "left"}}
        ]}
        """.utf8)).children
        try doc.apply(.insertNode(EditOperation.InsertNode(node: added[0], parentID: "Board")))
        try doc.apply(.insertNode(EditOperation.InsertNode(node: added[1])))
        return doc
    }

    /// The slots a plan writes a `children` override of, as `ref|key`.
    private func childrenWrites(_ plan: PastePlan) -> [String] {
        plan.operations.compactMap { operation in
            guard case let .overrideDescendant(op) = operation, op.properties["children"] != nil else { return nil }
            return "\(op.refNodeID)|\(op.descendantID)"
        }
    }

    /// The node JSON a fill holds under an id.
    private func fillNode(_ id: String, key: String, of refID: String, in doc: EditableDocument) -> [String: AnyCodable]? {
        guard case let .array(children)? = SlotScreenFixture.entry(key, of: refID, in: doc)?["children"] else { return nil }
        return SlotJSON.node(id, in: children)
    }

    /// The id a paste's root answers to in a fill: the expanded id's last step.
    private func localID(_ expandedID: String) -> String {
        expandedID.split(separator: "/").last.map(String.init) ?? expandedID
    }

    @Test("Pasting into a stack slot writes one override, the copy last in the fill, in the flow")
    func insideStackSlot() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        let plan = try clip.plan(into: doc, at: .inside(containerID: "Filled/List"))
        try PasteFixture.apply(plan, to: doc)

        #expect(childrenWrites(plan) == ["Filled|List"])
        #expect(PasteFixture.contentInserts(plan).isEmpty, "nothing is inserted into the store")
        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(pasted == "Filled/\(localID(pasted))")
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row2", "Row3", localID(pasted)])
        let node = try #require(fillNode(localID(pasted), key: "List", of: "Filled", in: doc))
        #expect(node["x"] == nil && node["y"] == nil, "a stack places it")
        #expect(node["name"] == .string("Loose"))
    }

    @Test("Pasting with slot content selected lands right after it in the fill")
    func afterSlotContent() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        let plan = try clip.plan(into: doc, at: .after(siblingID: "Filled/Row2/ItemB"))
        try PasteFixture.apply(plan, to: doc)

        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(childrenWrites(plan) == ["Filled|List"])
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row2", localID(pasted), "Row3"])
    }

    @Test("Pasting into a slot that shows its default content copies it into a fill first")
    func insideDefaultSlot() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        let plan = try clip.plan(into: doc, at: .inside(containerID: "Default/List"))
        try PasteFixture.apply(plan, to: doc)

        let content = try #require(doc.slot("Default/List")?.contentIDs)
        #expect(content.count == 2)
        #expect(content.last == plan.insertedRootIDs.first)
        #expect(!content.contains("Default/Empty1/EmptyState"), "the default content was copied with fresh ids")
    }

    @Test("Pasting into a free slot keeps the copy's offset from the parent it was copied out of")
    func insideFreeSlot() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        let plan = try clip.plan(into: doc, at: .inside(containerID: "FreeInst/Area"))
        try PasteFixture.apply(plan, to: doc)

        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(childrenWrites(plan) == ["FreeInst|Area"])
        let node = try #require(fillNode(localID(pasted), key: "Area", of: "FreeInst", in: doc))
        #expect(node["x"] == .int(10) && node["y"] == .int(10))
    }

    @Test("Pasting beside content in a free slot puts the copy to its right, top-aligned")
    func besideInFreeSlot() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        let plan = try clip.plan(into: doc, at: .after(siblingID: "FreeInst/Dot"))
        try PasteFixture.apply(plan, to: doc)

        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(SlotScreenFixture.fillIDs("Area", of: "FreeInst", in: doc) == ["Dot", localID(pasted)])
        let node = try #require(fillNode(localID(pasted), key: "Area", of: "FreeInst", in: doc))
        #expect(node["x"] == .int(35) && node["y"] == .int(6), "Dot ends at 15; the gap is 20")
    }

    @Test("Connectors pasted into a slot stay at the top level, their ends naming the copies in the fill")
    func connectors() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose", "Loose2"], from: doc)

        let plan = try clip.plan(into: doc, at: .inside(containerID: "Filled/List"))
        try PasteFixture.apply(plan, to: doc)

        let connector = try #require(plan.insertedConnectorIDs.first)
        let insert = try #require(PasteFixture.inserts(plan).first { $0.node.id == connector })
        #expect(insert.parentID == nil)
        #expect(ConnectorFixture.ends(of: doc.node(id: connector)) == plan.insertedRootIDs)
        #expect(plan.droppedConnectorIDs.isEmpty)
    }

    @Test("A paste into a slot that would make a component contain itself is refused")
    func loop() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["PanelInst"], from: doc)

        #expect {
            try clip.plan(into: doc, at: .inside(containerID: "PScr/List"))
        } throws: { error in
            guard case .wouldCloseComponentLoop? = error as? PasteError else { return false }
            return true
        }
    }

    @Test("A paste that brings a component writes its definition before the fill that places it")
    func carriedComponent() throws {
        let source = try PasteFixture.document("""
        {"version": "2.19", "children": [
          {"id": "Chip", "type": "frame", "name": "Chip", "reusable": true, "x": 0, "y": 0,
           "width": 40, "height": 20, "layout": "none"},
          {"id": "ChipI", "type": "ref", "ref": "Chip", "name": "Chip Instance", "x": 100, "y": 0}
        ]}
        """)
        let clip = try PenClip.extract(nodeIDs: ["ChipI"], from: source)
        let doc = try document()

        let plan = try clip.plan(into: doc, at: .inside(containerID: "Filled/List"))
        try PasteFixture.apply(plan, to: doc)

        #expect(doc.slot("Filled/List")?.contentIDs.count == 4)
        #expect(plan.insertedRootIDs.first.map { doc.slot("Filled/List")?.contentIDs.last == $0 } == true)
    }

    @Test("Pasting into an instance in a slot is refused: it is not a container")
    func intoInstanceInSlot() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        #expect(throws: PasteError.notAContainer(id: "Filled/Row2/ItemB")) {
            try clip.plan(into: doc, at: .inside(containerID: "Filled/Row2/ItemB"))
        }
    }

    @Test("Pasting into an instance outside its slots is refused")
    func outsideSlots() throws {
        let doc = try document()
        let clip = try PenClip.extract(nodeIDs: ["Loose"], from: doc)

        #expect {
            try clip.plan(into: doc, at: .after(siblingID: "Filled/Title"))
        } throws: { error in
            guard case let .slotRefused(refusal)? = error as? PasteError else { return false }
            return refusal.code == .insideInstance
        }
    }
}
