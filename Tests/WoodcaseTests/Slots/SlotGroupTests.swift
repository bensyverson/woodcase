//
//  SlotGroupTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Group, Frame Selection and Ungroup inside an instance's slot content, each written as
/// one `children` override of the slot, nothing moving on the canvas (Penumbra spec
/// §13.5 rule 4, §14).
@MainActor
struct SlotGroupTests {
    /// The slots a plan writes a `children` override of, as `ref|key`.
    private func childrenWrites(_ operations: [EditOperation]) -> [String] {
        operations.compactMap { operation in
            guard case let .overrideDescendant(op) = operation, op.properties["children"] != nil else { return nil }
            return "\(op.refNodeID)|\(op.descendantID)"
        }
    }

    /// The node JSON a fill holds under an id.
    private func fillNode(_ id: String, key: String, of refID: String, in doc: EditableDocument) -> [String: AnyCodable]? {
        guard case let .array(children)? = SlotScreenFixture.entry(key, of: refID, in: doc)?["children"] else { return nil }
        return SlotJSON.node(id, in: children)
    }

    /// The ids of a node JSON's children.
    private func childIDs(of node: [String: AnyCodable]?) -> [String]? {
        guard case let .array(children)? = node?["children"] else { return nil }
        return children.compactMap(SlotJSON.id(of:))
    }

    /// Where a node of the expanded document is drawn on the canvas.
    private func corners(of id: String, in doc: EditableDocument) -> [PenPoint]? {
        let layout = SlotScreenFixture.layout(of: doc)
        return PenLayoutEngine.canvasPlacement(of: id, in: layout.document, layoutRects: layout.rects)?.corners
    }

    /// The id a node answers to in a fill: an expanded id's last step.
    private func localID(_ expandedID: String) -> String {
        expandedID.split(separator: "/").last.map(String.init) ?? expandedID
    }

    private let rows = ["Filled/Row1/ItemA", "Filled/Row2/ItemB"]

    // MARK: - Group

    @Test("Grouping slot content writes one override: the group in the flow, the members free inside it")
    func groupInAFill() throws {
        let doc = try SlotScreenFixture.document()
        let before = rows.map { corners(of: $0, in: doc) }

        let plan = try EditPlanner.planGroup(nodeIDs: rows, kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        #expect(plan.operations.count == 1)
        let group = localID(plan.wrapperID)
        #expect(plan.wrapperID == "Filled/\(group)")
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == [group, "Row3"])
        let wrapper = fillNode(group, key: "List", of: "Filled", in: doc)
        #expect(wrapper?["type"] == .string("group"))
        #expect(wrapper?["x"] == nil, "the stack places the group")
        #expect(childIDs(of: wrapper) == ["Row1", "Row2"])
        #expect(fillNode("Row2", key: "List", of: "Filled", in: doc)?["y"] == .int(48))
        #expect(rows.map { corners(of: $0, in: doc) } == before, "nothing moves")
    }

    @Test("Frame Selection on slot content wraps it in a free frame sized to the members")
    func frameInAFill() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planGroup(nodeIDs: rows, kind: .frame, in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let wrapper = fillNode(localID(plan.wrapperID), key: "List", of: "Filled", in: doc)
        #expect(wrapper?["type"] == .string("frame"))
        #expect(wrapper?["layout"] == .string("none"))
        #expect(wrapper?["width"] == .int(200) && wrapper?["height"] == .int(104))
    }

    @Test("Grouping default content copies it into a fill first")
    func groupDefault() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planGroup(
            nodeIDs: ["Default/Empty1/EmptyState"], kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(plan.materializedSlotIDs == ["Default/List"])
        #expect(plan.renamed("Default/Empty1/EmptyState") != "Default/Empty1/EmptyState")
        #expect(doc.slot("Default/List")?.contentIDs == [plan.wrapperID])
    }

    @Test("A name given to Group rides the wrapper")
    func named() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planGroup(
            nodeIDs: rows, kind: .group, named: "Group 2", in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(fillNode(localID(plan.wrapperID), key: "List", of: "Filled", in: doc)?["name"] == .string("Group 2"))
    }

    @Test("A name given to Group outside slots rides the wrapper's insert")
    func namedStored() throws {
        let doc = try SlotScreenFixture.document()

        let plan = try EditPlanner.planGroup(
            nodeIDs: ["Loose"], kind: .group, named: "Group", in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.node(id: plan.wrapperID)?.common.name == "Group")
    }

    @Test("Grouping slot content with a stored node drawn on top of it is refused")
    func storedFront() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planGroup(
                nodeIDs: ["Filled/Row1/ItemA", "Loose"], kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc)
            )
        }
        #expect(refusal?.code == .insideInstance)
    }

    @Test("Grouping an instance's own node is still refused")
    func outsideSlots() throws {
        let doc = try SlotScreenFixture.document()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planGroup(nodeIDs: ["Filled/Title"], kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        }
        #expect(refusal?.code == .insideInstance)
    }

    // MARK: - Ungroup

    /// The fixture with `Row1` and `Row2` of `Filled` grouped, and the group's expanded id.
    private func grouped() throws -> (EditableDocument, String) {
        let doc = try SlotScreenFixture.document()
        let plan = try EditPlanner.planGroup(nodeIDs: rows, kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(plan.operations, to: doc)
        return (doc, plan.wrapperID)
    }

    @Test("Ungrouping a group in a fill writes one override, its children back in the flow in its place")
    func ungroupInAFill() throws {
        let (doc, group) = try grouped()
        let before = rows.map { corners(of: $0, in: doc) }

        let plan = try EditPlanner.planUngroup(groupIDs: [group], in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row2", "Row3"])
        #expect(fillNode("Row2", key: "List", of: "Filled", in: doc)?["y"] == nil, "the stack places them again")
        #expect(plan.placedIDs == rows)
        #expect(rows.map { corners(of: $0, in: doc) } == before, "nothing moves")
    }

    @Test("Ungrouping a group in a fill deletes a connector attached to the group itself")
    func ungroupConnector() throws {
        let (doc, group) = try grouped()
        let connector = try PenParser.parse(Data("""
        {"version": "2.19", "children": [
          {"type": "connection", "id": "KG", "source": {"path": "\(group)", "anchor": "right"},
           "target": {"path": "Loose", "anchor": "left"}},
          {"type": "connection", "id": "KR", "source": {"path": "Filled/Row1", "anchor": "right"},
           "target": {"path": "Loose", "anchor": "left"}}
        ]}
        """.utf8)).children
        for node in connector {
            try doc.apply(.insertNode(EditOperation.InsertNode(node: node)))
        }

        let plan = try EditPlanner.planUngroup(groupIDs: [group], in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(doc.node(id: "KG") == nil)
        #expect(doc.node(id: "KR") != nil, "a child keeps its connectors")
    }

    @Test("Ungrouping two groups in one slot writes it once")
    func ungroupTwo() throws {
        let doc = try SlotScreenFixture.document()
        let first = try EditPlanner.planGroup(nodeIDs: ["Filled/Row1/ItemA"], kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(first.operations, to: doc)
        let second = try EditPlanner.planGroup(nodeIDs: ["Filled/Row3/ItemA"], kind: .group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        try SlotScreenFixture.apply(second.operations, to: doc)

        let plan = try EditPlanner.planUngroup(
            groupIDs: [first.wrapperID, second.wrapperID], in: doc, layout: SlotScreenFixture.layout(of: doc)
        )
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(childrenWrites(plan.operations) == ["Filled|List"])
        #expect(SlotScreenFixture.fillIDs("List", of: "Filled", in: doc) == ["Row1", "Row2", "Row3"])
        #expect(plan.placedIDs == ["Filled/Row1/ItemA", "Filled/Row3/ItemA"])
    }

    @Test("Ungrouping stored groups plans what Ungroup plans for each, front to back")
    func ungroupStored() throws {
        let doc = try ConnectorFixture.document()
        let layout = PenLayoutState(document: PenVariableResolver.resolve(doc.expandedDocument().0))

        let plan = try EditPlanner.planUngroup(groupIDs: ["CardA"], in: doc, layout: layout)

        let single = try EditPlanner.planUngroup(groupID: "CardA", in: doc, layout: layout)
        #expect(plan.operations == single)
        #expect(plan.placedIDs == ["Title"])
    }

    @Test("The one-group Ungroup still refuses slot content, so plans are never concatenated over a stale fill")
    func singleRefuses() throws {
        let (doc, group) = try grouped()

        let refusal = SlotScreenFixture.refusal { () throws(EditRefusal) in
            try EditPlanner.planUngroup(groupID: group, in: doc, layout: SlotScreenFixture.layout(of: doc))
        }
        #expect(refusal?.code == .insideInstance)
    }
}
