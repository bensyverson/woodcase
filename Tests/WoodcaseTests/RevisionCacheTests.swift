//
//  RevisionCacheTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The revision cache has to be invisible.
///
/// Every test here warms the cache over the whole document, makes one kind of edit, and
/// then compares every node's revision with the revision a document built from scratch
/// out of the same state computes. A cache that survives an edit it should not have is
/// exactly the failure this catches, and it is the only evidence that
/// ``EditableDocument/revision(of:)`` still means what its callers think it means.
@MainActor
struct RevisionCacheTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    /// The addressing fixture: a two-branch dashboard, a reusable component with an
    /// instance that overrides two of its descendants, and a component nested inside
    /// that component.
    private func document() throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: "addressing", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("addressing.pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Reads every node's revision, filling the cache.
    @discardableResult
    private func warm(_ document: EditableDocument) -> [String: String] {
        revisions(of: document)
    }

    /// Every node's revision as the document answers it now — from the cache where it
    /// has an entry.
    private func revisions(of document: EditableDocument) -> [String: String] {
        document.nodes.keys.reduce(into: [:]) { $0[$1] = document.revision(of: $1) }
    }

    /// Every node's revision as a document with no cache at all computes it.
    private func scratchRevisions(of document: EditableDocument) -> [String: String] {
        let scratch = EditableDocument(from: document.materialize())
        return revisions(of: scratch)
    }

    /// A text node to insert or move around.
    private func loose(id: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: "Loose \(id)"),
            kind: .text(PenNode.TextData(content: .literal("loose")))
        )
    }

    // MARK: - The cache agrees with a from-scratch recompute

    @Test("A property set leaves every cached revision equal to a from-scratch recompute")
    func setPropertiesAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl01", properties: ["kind.content": .string("Edited")]
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A common update leaves every cached revision equal to a from-scratch recompute")
    func updateCommonAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "Hdr01", common: PenNodeCommon(name: "Renamed")
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("An insert leaves every cached revision equal to a from-scratch recompute")
    func insertAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.insertNode(EditOperation.InsertNode(
            node: loose(id: "New01"), parentID: "Hdr01"
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A move leaves every cached revision equal to a from-scratch recompute")
    func moveAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "Ttl01", newParentID: "Body1", index: 0
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A delete leaves every cached revision equal to a from-scratch recompute")
    func deleteAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Ttl01")))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("An override leaves every cached revision equal to a from-scratch recompute")
    func overrideAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "Nav01", descendantID: "Lbl01", properties: ["content": .string("Home")]
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A subtree replacement leaves every cached revision equal to a from-scratch recompute")
    func replaceSubtreeAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(node: PenNode(
            id: "Hdr01",
            common: PenNodeCommon(name: "Header"),
            kind: .frame(PenNode.FrameData(
                width: .fixed(800), height: .fixed(64), children: [loose(id: "Rep01")]
            ))
        ))))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A detach leaves every cached revision equal to a from-scratch recompute")
    func detachAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.detachRef(EditOperation.DetachRef(refNodeID: "Nav01")))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("A remote CRDT edit leaves every cached revision equal to a from-scratch recompute")
    func remoteEditAgreesWithScratch() throws {
        guard let url = Bundle.module.url(
            forResource: "addressing", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("addressing.pen")
        }
        let parsed = try PenParser.parse(contentsOf: url)
        let peerA = EditableDocument(from: parsed, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: parsed, peerID: PeerID(rawValue: "peerB"))
        warm(peerB)

        let ops = try peerA.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "Ttl01", common: PenNodeCommon(name: "Edited")
        )))
        peerB.applyRemote(ops)

        #expect(revisions(of: peerB) == scratchRevisions(of: peerB))
    }

    @Test("A document-level edit leaves the document revision equal to a from-scratch recompute")
    func variableEditAgreesWithScratch() throws {
        let document = try document()
        warm(document)
        let before = document.documentRevision

        try document.apply(.addVariable(EditOperation.AddVariable(
            name: "spacing", variable: PenVariable(type: .number, value: .simple(.int(16)))
        )))

        #expect(document.documentRevision != before)
        #expect(document.documentRevision == EditableDocument(from: document.materialize()).documentRevision)
    }

    // MARK: - What the cache holds

    @Test("Reading every node's revision caches every node")
    func aFullReadCachesEveryNode() throws {
        let document = try document()
        warm(document)

        #expect(document.revisionCache?.entries.count == document.nodes.count)
    }

    @Test("An edit forgets the node and its ancestors, and keeps everything else")
    func anEditForgetsTheSpineOnly() throws {
        let document = try document()
        warm(document)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl01", properties: ["kind.content": .string("Edited")]
        )))

        let entries = try #require(document.revisionCache?.entries)
        // Ttl01's spine: itself, Hdr01, Dash1.
        #expect(entries["Ttl01"] == nil)
        #expect(entries["Hdr01"] == nil)
        #expect(entries["Dash1"] == nil)
        // Siblings, cousins and the whole component branch are untouched.
        #expect(entries["Unn01"] != nil)
        #expect(entries["Body1"] != nil)
        #expect(entries["Btn01"] != nil)
        #expect(entries["Nav01"] != nil)
    }

    // MARK: - Spine scoping

    @Test("A property edit changes the revision of the node and its ancestors only")
    func aPropertyEditChangesTheSpineOnly() throws {
        let document = try document()
        let before = warm(document)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl01", properties: ["kind.content": .string("Edited")]
        )))
        let after = revisions(of: document)

        let spine: Set = ["Ttl01", "Hdr01", "Dash1"]
        for id in before.keys.sorted() {
            if spine.contains(id) {
                #expect(after[id] != before[id], "\(id) is on the spine and should have moved")
            } else {
                #expect(after[id] == before[id], "\(id) is off the spine and should not have moved")
            }
        }
    }

    @Test("Editing a component definition moves the definition's revision and every instance's")
    func aDefinitionEditMovesTheInstanceSpineToo() throws {
        let document = try document()
        let before = warm(document)
        let documentBefore = document.documentRevision

        // Lbl01 is a child of the reusable Btn01, which Nav01 (under Body1, under
        // Dash1) is an instance of.
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Lbl01", properties: ["kind.content": .string("Press")]
        )))
        let after = revisions(of: document)

        #expect(after["Lbl01"] != before["Lbl01"])
        #expect(after["Btn01"] != before["Btn01"])
        #expect(document.documentRevision != documentBefore)
        // A ref's revision folds in the revision of the component it renders, so a
        // definition edit moves the instance and everything above it. **This is the
        // deliberate reversal** of the authored-only behavior this test asserted when
        // the cache landed: a rev is a rendered-premise pin, so that one token on a
        // frame covers what the frame draws. See ``TreeRow/rev`` and
        // `RevisionFoldTests`.
        #expect(after["Nav01"] != before["Nav01"])
        #expect(after["Body1"] != before["Body1"])
        #expect(after["Dash1"] != before["Dash1"])
    }

    @Test("A definition edit leaves every cached revision equal to a from-scratch recompute")
    func aDefinitionEditAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Lbl01", properties: ["kind.content": .string("Press")]
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("An edit to a nested component's definition agrees with a from-scratch recompute")
    func aNestedDefinitionEditAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        // Cnt01 is inside Bge01, which Bdg01 instantiates inside Btn01, which Nav01
        // instantiates in turn: two ref hops from the edit to the outermost instance.
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Cnt01", properties: ["kind.content": .string("9")]
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("Deleting a component's child agrees with a from-scratch recompute")
    func aDefinitionDeleteAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Lbl01")))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    @Test("Moving a node into a component agrees with a from-scratch recompute")
    func aMoveIntoAComponentAgreesWithScratch() throws {
        let document = try document()
        warm(document)

        try document.apply(.moveNode(EditOperation.MoveNode(
            nodeID: "Ttl01", newParentID: "Btn01", index: 0
        )))

        #expect(revisions(of: document) == scratchRevisions(of: document))
    }

    // MARK: - Replica independence

    @Test("Two documents loaded from the same bytes agree on every revision, before and after the same edit")
    func twoDocumentsFromTheSameBytesAgree() throws {
        guard let url = Bundle.module.url(
            forResource: "addressing", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("addressing.pen")
        }
        let data = try Data(contentsOf: url)
        let first = try EditableDocument(from: PenParser.parse(data))
        let second = try EditableDocument(from: PenParser.parse(data))

        #expect(revisions(of: first) == revisions(of: second))
        #expect(first.documentRevision == second.documentRevision)

        let edit = EditOperation.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl02", properties: ["kind.content": .string("Invoices")]
        ))
        try first.apply(edit)
        try second.apply(edit)

        #expect(revisions(of: first) == revisions(of: second))
        #expect(first.documentRevision == second.documentRevision)
    }
}
