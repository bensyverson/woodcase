//
//  DocumentSessionInvalidationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A committed change says what to re-derive: nodes, category, document-level keys.
struct DocumentSessionInvalidationTests {
    private let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))

    private func makeSession() -> DocumentSession {
        DocumentSession(document: SessionTestDocuments.make().materialize(), author: ana, file: nil, collaborative: false)
    }

    private func submit(_ operations: EditOperation..., in session: DocumentSession) throws -> ChangeInvalidation {
        try session.submit(.local(LocalEdit(operations: operations))).invalidation
    }

    @Test("a move names the node, its new parent and its old parent")
    func moveIncludesOldParent() throws {
        let session = makeSession()
        let invalidation = try submit(
            .moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2", index: 0)),
            in: session
        )
        #expect(invalidation.nodes.isSuperset(of: ["c2", "f1", "f2"]))
        #expect(invalidation.structural)
        #expect(invalidation.category == .structural)
        #expect(!invalidation.full)
        #expect(invalidation.documentLevel.isEmpty)
    }

    @Test("a move to the root marks the root order")
    func moveToRoot() throws {
        let session = makeSession()
        let invalidation = try submit(.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: nil)), in: session)
        #expect(invalidation.nodes.isSuperset(of: ["c2", "f1"]))
        #expect(invalidation.documentLevel == [.rootOrder])
    }

    @Test("a delete names the whole removed subtree and the parent it left")
    func deleteNamesSubtreeAndParent() throws {
        let session = makeSession()
        let invalidation = try submit(.deleteNode(EditOperation.DeleteNode(nodeID: "f2")), in: session)
        #expect(invalidation.nodes.isSuperset(of: ["f2", "c4"]))
        #expect(invalidation.structural)
        #expect(invalidation.documentLevel == [.rootOrder])
    }

    @Test("a detach names the ref and every node its expansion inserts")
    func detachNamesExpansion() throws {
        let session = makeSession()
        let change = try session.submit(.local(LocalEdit(operations: [
            .detachRef(EditOperation.DetachRef(refNodeID: "ref1")),
        ])))
        let inserted = change.applied.flatMap(\.inverse).compactMap { step -> String? in
            if case let .deleteNode(op) = step.operation { op.nodeID } else { nil }
        }
        #expect(change.invalidation.nodes.contains("ref1"))
        #expect(!inserted.isEmpty)
        #expect(change.invalidation.nodes.isSuperset(of: inserted))
        for id in inserted {
            #expect(session.document.descendantIDs(of: id).allSatisfy(change.invalidation.nodes.contains))
        }
        #expect(change.invalidation.structural)
    }

    @Test("a property write categorizes by what changed")
    func propertyCategory() throws {
        let session = makeSession()
        let width = try submit(
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["kind.width": 200])),
            in: session
        )
        #expect(width.nodes == ["c1"])
        #expect(width.category == .layout)
        #expect(!width.structural)

        let name = try submit(
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "N"])),
            in: session
        )
        #expect(name.category == .renderOnly)
    }

    @Test("a variable change is document-level and full")
    func variableIsFull() throws {
        let session = makeSession()
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        let invalidation = try submit(
            .updateVariable(EditOperation.UpdateVariable(name: "primary", variable: variable)),
            in: session
        )
        #expect(invalidation.nodes.isEmpty)
        #expect(invalidation.documentLevel == [.variable("primary")])
        #expect(invalidation.full)
        #expect(!invalidation.structural)
    }

    @Test("adding the first variable to a document without a table names the declared table")
    func declaredTable() throws {
        let session = DocumentSession(
            document: PenDocument(children: []), author: ana, file: nil, collaborative: false
        )
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#00ff00")))
        let invalidation = try submit(
            .addVariable(EditOperation.AddVariable(name: "accent", variable: variable)),
            in: session
        )
        #expect(invalidation.documentLevel == [.variable("accent"), .declaredTable(.variables)])
    }

    @Test("document properties map to their document-level keys")
    func documentProperties() throws {
        let session = makeSession()
        let invalidation = try submit(
            .setDocumentProperties(EditOperation.SetDocumentProperties(properties: ["fonts": [], "extras.future": 1])),
            in: session
        )
        #expect(invalidation.documentLevel == [.fonts, .extra("future")])
        #expect(invalidation.full)
    }

    @Test("a multi-op change merges each operation's invalidation")
    func merged() throws {
        let session = makeSession()
        let invalidation = try submit(
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["common.name": "N"])),
            .moveNode(EditOperation.MoveNode(nodeID: "c3", newParentID: "f2")),
            in: session
        )
        #expect(invalidation.nodes.isSuperset(of: ["c1", "c3", "f1", "f2"]))
        #expect(invalidation.category == .structural)
        #expect(invalidation.structural)
    }

    @Test("formUnion merges two invalidations")
    func formUnion() {
        var first = ChangeInvalidation(nodes: ["a"], category: .renderOnly)
        first.formUnion(ChangeInvalidation(nodes: ["b"], category: .layout, documentLevel: [.fonts], full: true))
        #expect(first == ChangeInvalidation(
            nodes: ["a", "b"], category: .layout, documentLevel: [.fonts], structural: false, full: true
        ))
    }
}
