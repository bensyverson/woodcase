//
//  OverrideTargetGuardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct OverrideTargetGuardTests {
    // MARK: - Helpers

    /// A `Button` component with two children, and one instance named `Submit`.
    private func makeEditable() -> EditableDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let icon = PenNode(
            id: "icon",
            common: PenNodeCommon(name: "Icon"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label, icon]))
        )
        let ref1 = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Submit"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        return EditableDocument(from: PenDocument(children: [component, ref1]))
    }

    /// The same component, wrapped in a `Card` component that holds an instance of it,
    /// with one instance of the card at root.
    private func makeNestedEditable() -> EditableDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData())
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(name: "Inner"),
            kind: .ref(PenNode.RefData(ref: "comp1"))
        )
        let outer = PenNode(
            id: "outer",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData(children: [inner]))
        )
        let ref2 = PenNode(
            id: "ref2",
            common: PenNodeCommon(name: "Card1"),
            kind: .ref(PenNode.RefData(ref: "outer"))
        )
        return EditableDocument(from: PenDocument(children: [component, outer, ref2]))
    }

    private func override(_ descendantID: String, on refID: String = "ref1") -> EditOperation {
        .overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: refID,
            descendantID: descendantID,
            properties: ["name": .string("OK")]
        ))
    }

    // MARK: - Refusal

    @Test("An override addressed to a nonexistent descendant lists the component's nodes")
    func overrideRefusesUnknownDescendant() {
        let editable = makeEditable()

        #expect(throws: EditingError.overrideTargetNotFound(
            refID: "ref1",
            descendantKey: "missing",
            candidates: [
                NodeAddressCandidate(id: "ref1/label", path: "Submit/Label"),
                NodeAddressCandidate(id: "ref1/icon", path: "Submit/Icon"),
            ]
        )) {
            try editable.apply(override("missing"))
        }

        // Nothing was written.
        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants == nil)
    }

    @Test("Every candidate the refusal lists is an address that resolves")
    func everyCandidateResolves() throws {
        let editable = makeNestedEditable()
        var listed: [NodeAddressCandidate] = []
        do {
            try editable.apply(override("missing", on: "ref2"))
            Issue.record("expected the override to be refused")
        } catch let EditingError.overrideTargetNotFound(_, _, candidates) {
            listed = candidates
        }

        #expect(!listed.isEmpty)
        for candidate in listed {
            #expect(throws: Never.self) { try editable.resolve(candidate.id) }
            #expect(throws: Never.self) { try editable.resolve(candidate.path) }
        }
    }

    @Test("A nonexistent nested descendant lists nested candidates by their full paths")
    func overrideRefusesUnknownNestedDescendant() {
        let editable = makeNestedEditable()

        #expect(throws: EditingError.overrideTargetNotFound(
            refID: "ref2",
            descendantKey: "inner/missing",
            candidates: [
                NodeAddressCandidate(id: "ref2/inner", path: "Card1/Inner"),
                NodeAddressCandidate(id: "ref2/inner/label", path: "Card1/Inner/Label"),
            ]
        )) {
            try editable.apply(override("inner/missing", on: "ref2"))
        }
    }

    @Test("An override in CRDT mode refuses without touching CRDT state")
    func overrideRefusesInCRDTMode() throws {
        let doc = PenDocument(children: [
            PenNode(
                id: "comp1",
                common: PenNodeCommon(name: "Button", reusable: true),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(id: "label", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData())),
                ]))
            ),
            PenNode(id: "ref1", common: PenNodeCommon(name: "Submit"), kind: .ref(PenNode.RefData(ref: "comp1"))),
        ])
        let peerA = EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA"))

        #expect(throws: EditingError.overrideTargetNotFound(
            refID: "ref1",
            descendantKey: "missing",
            candidates: [
                NodeAddressCandidate(id: "ref1/label", path: "Submit/Label"),
            ]
        )) {
            _ = try peerA.applyLocal(override("missing"))
        }

        #expect(peerA.pendingOperations(since: VectorClock()).isEmpty)
        guard case let .ref(refData) = peerA.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants == nil)
    }

    // MARK: - Acceptance

    @Test("An override on a real descendant is applied")
    func overrideAcceptsRealDescendant() throws {
        let editable = makeEditable()
        try editable.apply(override("label"))

        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["label"]?.properties["name"] == .string("OK"))
    }

    @Test("An override on the component's own root is applied")
    func overrideAcceptsComponentRoot() throws {
        let editable = makeEditable()
        try editable.apply(override("comp1"))

        guard case let .ref(refData) = editable.nodes["ref1"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["comp1"] != nil)
    }

    @Test("An override on a nested descendant key is applied")
    func overrideAcceptsNestedDescendant() throws {
        let editable = makeNestedEditable()
        try editable.apply(override("inner/label", on: "ref2"))

        guard case let .ref(refData) = editable.nodes["ref2"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["inner/label"]?.properties["name"] == .string("OK"))
    }

    @Test("An override on a ref whose component is missing is not refused")
    func overrideAcceptsWhenComponentIsUnknown() throws {
        let orphan = PenNode(
            id: "ref9",
            common: PenNodeCommon(name: "Orphan"),
            kind: .ref(PenNode.RefData(ref: "gone"))
        )
        let editable = EditableDocument(from: PenDocument(children: [orphan]))

        // The component is not in the registry, so there is nothing to check the key
        // against. Refusing here would reject a valid edit to a document whose
        // component lives in an import we have not resolved.
        try editable.apply(override("anything", on: "ref9"))

        guard case let .ref(refData) = editable.nodes["ref9"]?.kind else {
            Issue.record("Expected ref kind")
            return
        }
        #expect(refData.descendants?["anything"] != nil)
    }
}
