//
//  RevisionFoldTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A revision is a **rendered**-premise pin, not an authored-state one.
///
/// A `ref` stores the component's id and its overrides, not the component, so hashing
/// only what the file stores under a node would leave a frame full of instances
/// unmoved by the definition edit that redraws every one of them — the gap recorded at
/// `DemV8`'s integration and closed by the ruling on leaf `2NW90`.
/// ``EditableDocument/revision(of:)`` therefore folds the resolved component's revision
/// into a `ref` node's, so one token on a frame covers what that frame renders.
///
/// These tests pin the fold itself; `RevisionCacheTests` pins that the memoized answer
/// and a from-scratch recompute stay the same answer under it.
@MainActor
struct RevisionFoldTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    /// A fixture document, by file name.
    private func document(_ name: String) throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("\(name).pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Every node's revision.
    private func revisions(of document: EditableDocument) -> [String: String] {
        document.nodes.keys.reduce(into: [:]) { $0[$1] = document.revision(of: $1) }
    }

    /// Sets `content` on a text node, which is the smallest edit that moves a revision.
    private func edit(_ nodeID: String, to text: String, in document: EditableDocument) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: nodeID, properties: ["kind.content": .string(text)]
        )))
    }

    // MARK: - The fold

    @Test("A definition edit moves every instance's revision, and every ancestor above one")
    func aDefinitionEditMovesEveryInstanceSpine() throws {
        let document = try document("addressing")
        let before = revisions(of: document)

        // Lbl01 is a child of the reusable Btn01, which Nav01 — under Body1, under
        // Dash1 — is an instance of.
        try edit("Lbl01", to: "Press", in: document)
        let after = revisions(of: document)

        #expect(after["Lbl01"] != before["Lbl01"])
        #expect(after["Btn01"] != before["Btn01"])
        #expect(after["Nav01"] != before["Nav01"])
        #expect(after["Body1"] != before["Body1"])
        #expect(after["Dash1"] != before["Dash1"])
    }

    @Test("A definition edit leaves nodes that neither hold nor render it alone")
    func aDefinitionEditLeavesUnrelatedNodesAlone() throws {
        let document = try document("addressing")
        let before = revisions(of: document)

        try edit("Lbl01", to: "Press", in: document)
        let after = revisions(of: document)

        // The header branch holds no instance of Btn01.
        #expect(after["Hdr01"] == before["Hdr01"])
        #expect(after["Ttl01"] == before["Ttl01"])
        // The badge component is nested *inside* Btn01, not the other way round.
        #expect(after["Bge01"] == before["Bge01"])
    }

    @Test("A nested definition's edit reaches the outer instance through both refs")
    func aNestedDefinitionEditReachesTheOuterInstance() throws {
        let document = try document("addressing")
        let before = revisions(of: document)

        // Cnt01 is inside Bge01, which Bdg01 (inside Btn01) instantiates, which Nav01
        // instantiates in turn.
        try edit("Cnt01", to: "9", in: document)
        let after = revisions(of: document)

        #expect(after["Bge01"] != before["Bge01"])
        #expect(after["Bdg01"] != before["Bdg01"])
        #expect(after["Btn01"] != before["Btn01"])
        #expect(after["Nav01"] != before["Nav01"])
        #expect(after["Dash1"] != before["Dash1"])
    }

    @Test("An instance's own overrides still move its revision and nothing else's")
    func anOverrideMovesTheInstanceOnly() throws {
        let document = try document("addressing")
        let before = revisions(of: document)

        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Nav01", descendantID: "Lbl01", properties: ["content": .string("Home")]
        )))
        let after = revisions(of: document)

        #expect(after["Nav01"] != before["Nav01"])
        #expect(after["Body1"] != before["Body1"])
        #expect(after["Btn01"] == before["Btn01"])
        #expect(after["Lbl01"] == before["Lbl01"])
    }

    // MARK: - Repointing

    @Test("An instance covers the component it was repointed at, not the one it was authored with")
    func aRepointedInstanceCoversWhatItRenders() throws {
        let document = try document("ref-repoint-nested")

        // Before the repoint, Sht01 renders ShtC → Tab01 → PlnC, and TabCurrent is
        // nothing to do with it.
        let authored = try #require(document.revision(of: "Sht01"))
        try edit("Lbl02", to: "Current!", in: document)
        #expect(document.revision(of: "Sht01") == authored)

        // Repointing the sheet's nested tab at TabCurrent is authored state on Sht01,
        // so it moves Sht01's own revision …
        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Sht01", descendantID: "Tab01", properties: ["ref": .string("CurC")]
        )))
        let repointed = try #require(document.revision(of: "Sht01"))
        #expect(repointed != authored)

        // … and from now on Sht01 renders TabCurrent, so an edit to TabCurrent moves it.
        try edit("Lbl02", to: "Current!!", in: document)
        #expect(document.revision(of: "Sht01") != repointed)
    }

    // MARK: - Slot content

    @Test("An instance covers the components its slot content instantiates")
    func slotContentInstancesAreCovered() throws {
        let document = try document("slot-fill")
        let before = revisions(of: document)

        // Inst0 fills Card0's slot with Tag00, an instance of Badg0 written inside
        // Inst0's own `descendants` — so Inst0, and the page holding it, draw BTxt0.
        try edit("BTxt0", to: "changed", in: document)
        let after = revisions(of: document)

        #expect(after["Inst0"] != before["Inst0"])
        #expect(after["Page0"] != before["Page0"])
        #expect(document.revisionCoverage(of: "Inst0").contains("BTxt0"))
        // Inst1 leaves the slot empty and draws no badge.
        #expect(after["Inst1"] == before["Inst1"])
    }

    // MARK: - Cycles

    @Test("A component that contains an instance of itself still hashes, and hashes the same twice")
    func aComponentCycleTerminates() {
        let cyclic = PenDocument(children: [
            PenNode(
                id: "CmpA",
                common: PenNodeCommon(name: "A", reusable: true),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "RefA",
                        common: PenNodeCommon(name: "Self"),
                        kind: .ref(PenNode.RefData(ref: "CmpA"))
                    ),
                ]))
            ),
            PenNode(
                id: "Page1",
                common: PenNodeCommon(name: "Page"),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "Inst1",
                        common: PenNodeCommon(name: "Instance"),
                        kind: .ref(PenNode.RefData(ref: "CmpA"))
                    ),
                ]))
            ),
        ])

        let first = EditableDocument(from: cyclic)
        let second = EditableDocument(from: cyclic)

        // Terminating at all is the first assertion; agreeing is the second, and it is
        // what says the cut is a property of the document rather than of the walk.
        #expect(first.revision(of: "Inst1") != nil)
        #expect(first.revision(of: "Inst1") == second.revision(of: "Inst1"))
        #expect(first.revision(of: "CmpA") == second.revision(of: "CmpA"))
        #expect(first.documentRevision == second.documentRevision)
    }

    @Test("A cyclic component's revisions do not depend on which node was asked for first")
    func aCycleIsAskingOrderIndependent() {
        let cyclic = PenDocument(children: [
            PenNode(
                id: "CmpA",
                common: PenNodeCommon(name: "A", reusable: true),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "RefB",
                        common: PenNodeCommon(name: "ToB"),
                        kind: .ref(PenNode.RefData(ref: "CmpB"))
                    ),
                ]))
            ),
            PenNode(
                id: "CmpB",
                common: PenNodeCommon(name: "B", reusable: true),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "RefA",
                        common: PenNodeCommon(name: "ToA"),
                        kind: .ref(PenNode.RefData(ref: "CmpA"))
                    ),
                ]))
            ),
        ])

        let outsideIn = EditableDocument(from: cyclic)
        _ = outsideIn.revision(of: "CmpA")
        let insideOut = EditableDocument(from: cyclic)
        _ = insideOut.revision(of: "RefA")

        #expect(outsideIn.revision(of: "CmpB") == insideOut.revision(of: "CmpB"))
        #expect(outsideIn.revision(of: "CmpA") == insideOut.revision(of: "CmpA"))
    }
}
