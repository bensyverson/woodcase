//
//  EditOperationReplaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditOperation/replaceSubtree(_:)`` swaps what is under a node without moving the
/// node: the id, the parent and the index among siblings all survive, and the inverse
/// puts the old subtree back exactly as it was.
@MainActor
@Suite("replaceSubtree keeps the node's place")
struct EditOperationReplaceTests {
    // MARK: - Fixtures

    /// `Canvas > [Title(text), Card > [Old(rect)], Tail(text)]`
    private func makeDocument() -> EditableDocument {
        let old = PenNode(id: "old01", common: PenNodeCommon(name: "Old"), kind: .rectangle(PenNode.RectangleData()))
        let card = PenNode(
            id: "crd01",
            common: PenNodeCommon(name: "Card"),
            kind: .frame(PenNode.FrameData(children: [old]))
        )
        let title = PenNode(id: "ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData()))
        let tail = PenNode(id: "tal01", common: PenNodeCommon(name: "Tail"), kind: .text(PenNode.TextData()))
        let canvas = PenNode(
            id: "cnv01",
            common: PenNodeCommon(name: "Canvas"),
            kind: .frame(PenNode.FrameData(children: [title, card, tail]))
        )
        return EditableDocument(from: PenDocument(children: [canvas]))
    }

    /// A reusable `Component > [Label]` with one `ref` instance beside it.
    private func makeComponentDocument() -> EditableDocument {
        let label = PenNode(id: "lbl01", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData()))
        let component = PenNode(
            id: "cmp01",
            common: PenNodeCommon(name: "Component", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let instance = PenNode(
            id: "chi01",
            common: PenNodeCommon(name: "Chip"),
            kind: .ref(PenNode.RefData(ref: "cmp01"))
        )
        let board = PenNode(
            id: "brd01",
            common: PenNodeCommon(name: "Board"),
            kind: .frame(PenNode.FrameData(children: [instance]))
        )
        return EditableDocument(from: PenDocument(children: [component, board]))
    }

    /// A replacement for `Card`, carrying the id it must keep.
    private func replacement(
        id: String = "crd01",
        name: String = "Card",
        children: [PenNode]
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .frame(PenNode.FrameData(children: children))
        )
    }

    // MARK: - Place

    @Test("The replaced node keeps its id, its parent and its index among siblings")
    func keepsItsPlace() throws {
        let document = makeDocument()
        let fresh = PenNode(id: "new01", common: PenNodeCommon(name: "New"), kind: .text(PenNode.TextData()))

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
            node: replacement(children: [fresh])
        )))

        #expect(document.parents["crd01"] == "cnv01")
        #expect(document.children["cnv01"] == ["ttl01", "crd01", "tal01"])
        #expect(document.children["crd01"] == ["new01"])
        #expect(document.nodes["old01"] == nil)
        #expect(document.namePath(of: "new01") == "Canvas/Card/New")
    }

    @Test("A replaced root node keeps its position in the root order")
    func keepsItsRootPosition() throws {
        let document = makeDocument()
        let second = PenNode(id: "sec01", common: PenNodeCommon(name: "Second"), kind: .frame(PenNode.FrameData()))
        try document.apply(.insertNode(EditOperation.InsertNode(node: second)))

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
            node: PenNode(
                id: "cnv01",
                common: PenNodeCommon(name: "Canvas"),
                kind: .frame(PenNode.FrameData(children: []))
            )
        )))

        #expect(document.rootOrder == ["cnv01", "sec01"])
        #expect(document.parents["cnv01"] == nil)
    }

    // MARK: - Inverse

    @Test("The inverse restores the previous subtree exactly")
    func inverseRestoresTheOldSubtree() throws {
        let document = makeDocument()
        let before = try document.materializeSubtree(rootID: "crd01")
        let operation = EditOperation.replaceSubtree(EditOperation.ReplaceSubtree(
            node: replacement(children: [
                PenNode(id: "new01", common: PenNodeCommon(name: "New"), kind: .text(PenNode.TextData())),
            ])
        ))

        let inverse = try document.prepareInverse(of: operation)
        try document.apply(operation)
        #expect(inverse.count == 1)
        for step in inverse {
            try document.apply(step)
        }

        #expect(try document.materializeSubtree(rootID: "crd01") == before)
        #expect(document.children["cnv01"] == ["ttl01", "crd01", "tal01"])
    }

    @Test("An empty children array survives the round trip, rather than becoming absent")
    func inverseKeepsAnEmptyChildrenArray() throws {
        let empty = PenNode(
            id: "emp01",
            common: PenNodeCommon(name: "Empty"),
            kind: .frame(PenNode.FrameData(children: []))
        )
        let document = EditableDocument(from: PenDocument(children: [empty]))
        let operation = EditOperation.replaceSubtree(EditOperation.ReplaceSubtree(
            node: PenNode(
                id: "emp01",
                common: PenNodeCommon(name: "Empty"),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(id: "kid01", common: PenNodeCommon(name: "Kid"), kind: .text(PenNode.TextData())),
                ]))
            )
        ))

        let inverse = try document.prepareInverse(of: operation)
        try document.apply(operation)
        for step in inverse {
            try document.apply(step)
        }

        #expect(document.materialize().children == [empty])
    }

    // MARK: - Ids

    @Test("A descendant id already held elsewhere in the document is refused")
    func refusesADuplicateDescendantID() {
        let document = makeDocument()
        #expect(throws: EditingError.duplicateNodeID(id: "ttl01")) {
            try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
                node: replacement(children: [
                    PenNode(id: "ttl01", common: PenNodeCommon(name: "Clash"), kind: .text(PenNode.TextData())),
                ])
            )))
        }
        #expect(document.namePath(of: "ttl01") == "Canvas/Title")
    }

    @Test("An id the replaced subtree itself held is free to reuse")
    func reusesAnIDFromTheSubtreeItReplaces() throws {
        let document = makeDocument()

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
            node: replacement(children: [
                PenNode(id: "old01", common: PenNodeCommon(name: "Reborn"), kind: .text(PenNode.TextData())),
            ])
        )))

        #expect(document.namePath(of: "old01") == "Canvas/Card/Reborn")
    }

    @Test("A subtree that uses one id twice is refused")
    func refusesADuplicateWithinTheSubtree() {
        let document = makeDocument()
        #expect(throws: EditingError.duplicateNodeID(id: "twn01")) {
            try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
                node: replacement(children: [
                    PenNode(id: "twn01", common: PenNodeCommon(name: "One"), kind: .text(PenNode.TextData())),
                    PenNode(id: "twn01", common: PenNodeCommon(name: "Two"), kind: .text(PenNode.TextData())),
                ])
            )))
        }
    }

    @Test("Replacing a node the document does not hold is refused")
    func refusesAnUnknownNode() {
        let document = makeDocument()
        #expect(throws: EditingError.nodeNotFound(id: "zz999")) {
            try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
                node: replacement(id: "zz999", name: "Ghost", children: [])
            )))
        }
    }

    // MARK: - Components

    @Test("A reusable definition with instances may be rebuilt, keeping its type")
    func rebuildsAComponentOfTheSameType() throws {
        let document = makeComponentDocument()

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
            node: PenNode(
                id: "cmp01",
                common: PenNodeCommon(name: "Component", reusable: true),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(id: "hdl01", common: PenNodeCommon(name: "Headline"), kind: .text(PenNode.TextData())),
                ]))
            )
        )))

        #expect(document.children["cmp01"] == ["hdl01"])
        #expect(document.componentRegistry["cmp01"] != nil)
        let expanded = try document.expandRef(nodeID: "chi01")
        #expect(expanded.expandedNode.kind.inlineChildren.map(\.common.name) == ["Headline"])
    }

    @Test("Changing the root type of a reusable definition with instances is refused")
    func refusesAWholeKindSwapOnALiveComponent() {
        let document = makeComponentDocument()
        #expect(throws: EditingError.componentTypeChange(
            componentID: "cmp01", from: "frame", to: "text", instanceIDs: ["chi01"]
        )) {
            try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
                node: PenNode(
                    id: "cmp01",
                    common: PenNodeCommon(name: "Component", reusable: true),
                    kind: .text(PenNode.TextData())
                )
            )))
        }
        #expect(document.nodes["lbl01"] != nil)
    }

    @Test("Changing the root type of a reusable definition nothing points at is allowed")
    func allowsAKindSwapOnAnUnusedComponent() throws {
        let document = makeComponentDocument()
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "chi01")))

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
            node: PenNode(
                id: "cmp01",
                common: PenNodeCommon(name: "Component", reusable: true),
                kind: .text(PenNode.TextData())
            )
        )))

        #expect(document.nodes["cmp01"]?.kind.typeName == "text")
    }

    @Test("A replacement that would strand a nested component's instances is refused")
    func refusesToStrandInstances() {
        let document = makeComponentDocument()
        // Put the definition inside Board, beside the instance's parent, so replacing
        // Board would take the definition with it while the instance survives.
        let holder = PenNode(
            id: "hld01",
            common: PenNodeCommon(name: "Holder"),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(
                    id: "cmp02",
                    common: PenNodeCommon(name: "Inner", reusable: true),
                    kind: .frame(PenNode.FrameData())
                ),
            ]))
        )
        #expect(throws: Never.self) {
            try document.apply(.insertNode(EditOperation.InsertNode(node: holder)))
            try document.apply(.insertNode(EditOperation.InsertNode(
                node: PenNode(
                    id: "ins02",
                    common: PenNodeCommon(name: "InnerChip"),
                    kind: .ref(PenNode.RefData(ref: "cmp02"))
                ),
                parentID: "brd01"
            )))
        }

        #expect(throws: EditingError.componentHasInstances(componentID: "cmp02", instanceIDs: ["ins02"])) {
            try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(
                node: PenNode(
                    id: "hld01",
                    common: PenNodeCommon(name: "Holder"),
                    kind: .frame(PenNode.FrameData(children: []))
                )
            )))
        }
    }
}
