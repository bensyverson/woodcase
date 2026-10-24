//
//  DetachConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A detach keeps the connectors attached to the instance and to the nodes drawn inside
/// it: every end naming one is rewritten to the detached copy's derived id, in the same
/// edit, undone with it, and replicated with it.
@MainActor
struct DetachConnectorTests {
    /// The connectors the fixture gains, by id: source path, target path.
    private static let connectors: [(id: String, source: String, target: String)] = [
        ("KRoot", "Filled", "Loose"),
        ("KIn", "Filled/Title", "Loose"),
        ("KBoth", "Filled/Title", "Filled/List"),
        ("KFill", "Filled/Row1", "Loose"),
        ("KFillIn", "Filled/Row2/BLbl", "Loose"),
        ("KNest", "PanelInst/PScr/Title", "Loose"),
        ("KOther", "Default/Title", "Loose"),
    ]

    /// The slot-screen fixture with ``connectors`` at the top level.
    private func document(peerID: PeerID? = nil) throws -> EditableDocument {
        let parsed = try PenParser.parse(Data(SlotScreenFixture.json.utf8))
        let doc = if let peerID {
            EditableDocument(from: parsed, peerID: peerID)
        } else {
            EditableDocument(from: parsed)
        }
        for connector in Self.connectors {
            try doc.apply(.insertNode(EditOperation.InsertNode(node: PenNode(
                id: connector.id,
                common: PenNodeCommon(),
                kind: .connection(PenNode.ConnectionData(
                    source: PenNode.ConnectionData.Endpoint(path: connector.source, anchor: .right),
                    target: PenNode.ConnectionData.Endpoint(path: connector.target, anchor: .left)
                ))
            ))))
        }
        return doc
    }

    /// A connector's two end paths, source first.
    private func ends(_ id: String, in doc: EditableDocument) -> [String]? {
        ConnectorFixture.ends(of: doc.nodes[id])
    }

    /// The name of the node a path names, stored or drawn inside an instance — an
    /// instance by its own path, which its expanded root extends by the component root's
    /// id.
    private func name(at path: String, in doc: EditableDocument) -> String? {
        if let stored = doc.nodes[path] { return stored.common.name }
        guard let first = path.split(separator: "/").first.map(String.init),
              let expanded = try? doc.expandRef(nodeID: first).expandedNode
        else { return nil }
        func owner(_ id: String) -> String? {
            id.lastIndex(of: "/").map { String(id[..<$0]) }
        }
        var pending: [(node: PenNode, parent: String?)] = [(expanded, nil)]
        while let (node, parent) = pending.popLast() {
            if node.id == path { return node.common.name }
            if owner(node.id) == path, parent.flatMap(owner) != path { return node.common.name }
            pending.append(contentsOf: node.kind.inlineChildren.map { ($0, node.id) })
        }
        return nil
    }

    /// Every connector end's node name, by connector, so a test can check the ends still
    /// name the same nodes after an edit renames them.
    private func endNames(in doc: EditableDocument) -> [String: [String?]] {
        var names: [String: [String?]] = [:]
        for connector in Self.connectors {
            names[connector.id] = ends(connector.id, in: doc)?.map { name(at: $0, in: doc) }
        }
        return names
    }

    // MARK: - Detach

    @Test("Detaching an instance rewrites the ends naming it or a node inside it to the detached ids")
    func detachRewritesEnds() throws {
        let doc = try document()
        let names = endNames(in: doc)

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        #expect(ends("KRoot", in: doc) == [result.rootNodeID, "Loose"])
        #expect(ends("KIn", in: doc) == [result.idMapping["Filled/Title"] ?? "-", "Loose"])
        #expect(ends("KBoth", in: doc) == [result.idMapping["Filled/Title"] ?? "-", result.idMapping["Filled/List"] ?? "-"])
        #expect(ends("KOther", in: doc) == ["Default/Title", "Loose"])
        for id in ["KRoot", "KIn", "KBoth", "KFill", "KFillIn"] {
            let paths = try #require(ends(id, in: doc))
            #expect(paths.allSatisfy { doc.nodes[$0] != nil }, "\(id) still names a drawn node: \(paths)")
        }
        #expect(endNames(in: doc) == names)
    }

    @Test("Detaching an instance rewrites the ends naming nodes in its slot fill")
    func detachRewritesFillEnds() throws {
        let doc = try document()

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        let row1 = try #require(ends("KFill", in: doc)?.first)
        let label = try #require(ends("KFillIn", in: doc)?.first)
        #expect(doc.nodes[row1]?.common.name == "Row 1")
        #expect(doc.nodes[label] != nil)
        #expect(Set(result.idMapping.values).contains(row1))
        #expect(Set(result.idMapping.values).contains(label))
    }

    @Test("Detaching an instance rewrites an end inside a nested instance")
    func detachRewritesNestedEnds() throws {
        let doc = try document()
        let names = endNames(in: doc)

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "PanelInst"))

        let source = try #require(ends("KNest", in: doc)?.first)
        #expect(!source.hasPrefix("PanelInst"))
        #expect(ConnectorFixture.resolves(source, in: doc))
        #expect(source.split(separator: "/").first.map(String.init).map { Set(result.idMapping.values).contains($0) } == true)
        #expect(endNames(in: doc) == names)
    }

    @Test("Detaching an instance inside a component rewrites ends drawn through the component's instances")
    func detachInsideComponentRewritesInstanceEnds() throws {
        let doc = try document()
        let names = endNames(in: doc)

        let result = try doc.detachRef(EditOperation.DetachRef(refNodeID: "PScr"))

        let title = try #require(result.idMapping["PScr/Title"])
        #expect(ends("KNest", in: doc) == ["PanelInst/" + title, "Loose"])
        #expect(endNames(in: doc) == names)
    }

    @Test("A detach's prepared inverse puts the connector ends back")
    func detachUndoRestoresEnds() throws {
        let doc = try document()
        let before = doc.materialize()
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        let inverse = try doc.prepareInverse(of: op)
        try doc.apply(op)
        #expect(ends("KRoot", in: doc) != ["Filled", "Loose"])
        for step in inverse {
            try doc.apply(step)
        }

        #expect(doc.materialize() == before)
    }

    @Test("A detach's change keys name the connector ends it rewrites")
    func detachKeysNameRewrittenEnds() throws {
        let doc = try document()
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        let keys = try Set(ChangeKey.keys(of: op, in: doc))

        #expect(keys.contains(.property(node: "KIn", path: "kind.source")))
        #expect(keys.contains(.property(node: "KBoth", path: "kind.target")))
        #expect(!keys.contains { $0.nodeID == "KOther" })
    }

    // MARK: - Detaching delete

    @Test("A detaching delete rewrites the ends naming the instances it detaches, and undoes them")
    func detachingDeleteRewritesEnds() throws {
        let doc = try document()
        let before = doc.materialize()
        let names = endNames(in: doc)
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Screen", instances: .detach))

        let inverse = try doc.prepareInverse(of: op)
        try doc.apply(op)

        // Every stored instance of Screen is detached — Default, Filled, and PScr inside
        // Panel, which PanelInst draws — so every end is rewritten, KNest's inside the
        // instance of the component that held PScr.
        for connector in Self.connectors {
            let id = connector.id
            let paths = try #require(ends(id, in: doc))
            #expect(paths.allSatisfy { ConnectorFixture.resolves($0, in: doc) }, "\(id) dangles: \(paths)")
        }
        #expect(ends("KBoth", in: doc).map { $0.allSatisfy { doc.nodes[$0] != nil } } == true)
        #expect(endNames(in: doc) == names)

        for step in inverse {
            try doc.apply(step)
        }
        #expect(doc.materialize() == before)
    }

    // MARK: - Collaborative

    @Test("A collaborative detach replicates the rewritten ends to the other peer")
    func collaborativeDetachReplicatesEnds() throws {
        let peerA = try document(peerID: PeerID(rawValue: "peerA"))
        let peerB = try document(peerID: PeerID(rawValue: "peerB"))
        let op = EditOperation.detachRef(EditOperation.DetachRef(refNodeID: "Filled"))

        let inverse = try peerA.prepareInverse(of: op)
        let ops = try peerA.applyLocal(op)
        peerB.applyRemote(ops)

        let source = try #require(ends("KIn", in: peerA)?.first)
        #expect(source != "Filled/Title")
        #expect(peerA.nodes[source] != nil)
        for connector in Self.connectors {
            #expect(ends(connector.id, in: peerB) == ends(connector.id, in: peerA))
        }

        var undo: [CRDTOperation] = []
        for step in inverse {
            try undo.append(contentsOf: peerA.applyLocal(step))
        }
        peerB.applyRemote(undo)
        for connector in Self.connectors {
            #expect(ends(connector.id, in: peerA) == [connector.source, connector.target])
            #expect(ends(connector.id, in: peerB) == [connector.source, connector.target])
        }
    }
}
