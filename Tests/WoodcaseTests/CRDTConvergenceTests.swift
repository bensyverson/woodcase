//
//  CRDTConvergenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTConvergenceTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    // MARK: - Helpers

    private func makePair(from doc: PenDocument) -> (EditableDocument, EditableDocument) {
        let a = EditableDocument(from: doc, peerID: peerA)
        let b = EditableDocument(from: doc, peerID: peerB)
        return (a, b)
    }

    private func sync(_: EditableDocument, to target: EditableDocument, ops: [CRDTOperation]) {
        target.applyRemote(ops)
    }

    private func assertConverged(_ a: EditableDocument, _ b: EditableDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.rootOrder == b.rootOrder, "rootOrder diverged", sourceLocation: sourceLocation)
        #expect(a.nodes.keys.sorted() == b.nodes.keys.sorted(), "node keys diverged", sourceLocation: sourceLocation)
        for key in a.nodes.keys {
            #expect(a.nodes[key] == b.nodes[key], "node \(key) diverged", sourceLocation: sourceLocation)
        }
        #expect(a.children == b.children, "children diverged", sourceLocation: sourceLocation)
        #expect(a.parents == b.parents, "parents diverged", sourceLocation: sourceLocation)
        #expect(a.variables == b.variables, "variables diverged", sourceLocation: sourceLocation)
        #expect(a.imports == b.imports, "imports diverged", sourceLocation: sourceLocation)
        #expect(a.themes == b.themes, "themes diverged", sourceLocation: sourceLocation)
    }

    private func makeTestDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let text = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Text"),
            kind: .text(PenNode.TextData(width: .fixed(200)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect, text]))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - Two peers edit different properties of same node

    @Test("Two peers edit different properties → both preserved")
    func differentPropertiesBothPreserved() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // Peer A renames the rect
        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(name: "RenamedByA", opacity: .literal(1.0))
        )))

        // Peer B changes opacity
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(0.5))
        )))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should have A's name and B's opacity
        #expect(a.nodes["r1"]?.common.name == "RenamedByA")
        #expect(b.nodes["r1"]?.common.name == "RenamedByA")
        #expect(a.nodes["r1"]?.common.opacity == .literal(0.5))
        #expect(b.nodes["r1"]?.common.opacity == .literal(0.5))

        assertConverged(a, b)
    }

    // MARK: - Two peers edit same property → LWW winner, both converge

    @Test("Two peers edit same property → LWW winner, both converge")
    func samePropertyLWWConverges() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // Both rename r1
        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(name: "NameByA")
        )))
        let opsB = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(name: "NameByB")
        )))

        // Exchange — apply in both orders
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should converge to the same name (LWW picks one)
        #expect(a.nodes["r1"]?.common.name == b.nodes["r1"]?.common.name)
        assertConverged(a, b)
    }

    // MARK: - Two peers insert at same list position

    @Test("Two peers insert at same position → deterministic interleaving")
    func concurrentInsertsSamePosition() throws {
        let (a, b) = makePair(from: makeTestDoc())

        let nodeA = PenNode(
            id: "nA",
            common: PenNodeCommon(name: "InsertedByA"),
            kind: .rectangle(PenNode.RectangleData())
        )
        let nodeB = PenNode(
            id: "nB",
            common: PenNodeCommon(name: "InsertedByB"),
            kind: .rectangle(PenNode.RectangleData())
        )

        // Both insert into f1 at end
        let opsA = try a.applyLocal(.insertNode(EditOperation.InsertNode(node: nodeA, parentID: "f1")))
        let opsB = try b.applyLocal(.insertNode(EditOperation.InsertNode(node: nodeB, parentID: "f1")))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should see both nodes in children of f1, in the same order
        assertConverged(a, b)
        #expect(a.children["f1"]?.contains("nA") == true)
        #expect(a.children["f1"]?.contains("nB") == true)
    }

    // MARK: - Property-based random: N ops on A, M ops on B, exchange, converge

    @Test("Random property edits on A and B → converge after exchange")
    func randomPropertyEditsConverge() throws {
        let (a, b) = makePair(from: makeTestDoc())

        // A makes several edits
        let opsA1 = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "A1")
        )))
        let opsA2 = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "t1", common: PenNodeCommon(name: "A2")
        )))

        // B makes several edits
        let opsB1 = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1", common: PenNodeCommon(name: "B1")
        )))
        let opsB2 = try b.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "f1", common: PenNodeCommon(name: "B2")
        )))

        // Exchange all
        sync(a, to: b, ops: opsA1 + opsA2)
        sync(b, to: a, ops: opsB1 + opsB2)

        assertConverged(a, b)
    }

    // MARK: - Document-level convergence

    @Test("Concurrent variable edits converge")
    func concurrentVariableEditsConverge() throws {
        let (a, b) = makePair(from: makeTestDoc())

        let varA = PenVariable(type: .color, value: .simple(AnyCodable("#FF0000")))
        let varB = PenVariable(type: .color, value: .simple(AnyCodable("#00FF00")))

        let opsA = try a.applyLocal(.addVariable(EditOperation.AddVariable(name: "primary", variable: varA)))
        let opsB = try b.applyLocal(.addVariable(EditOperation.AddVariable(name: "secondary", variable: varB)))

        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should have both variables
        #expect(a.variables?["primary"] != nil)
        #expect(a.variables?["secondary"] != nil)
        assertConverged(a, b)
    }

    @Test("Concurrent import edits converge")
    func concurrentImportEditsConverge() throws {
        let (a, b) = makePair(from: makeTestDoc())

        let opsA = try a.applyLocal(.addImport(EditOperation.AddImport(alias: "icons", path: "./icons.pen")))
        let opsB = try b.applyLocal(.addImport(EditOperation.AddImport(alias: "buttons", path: "./buttons.pen")))

        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        #expect(a.imports?["icons"] != nil)
        #expect(a.imports?["buttons"] != nil)
        assertConverged(a, b)
    }

    @Test("Concurrent theme edits converge")
    func concurrentThemeEditsConverge() throws {
        let (a, b) = makePair(from: makeTestDoc())

        let opsA = try a.applyLocal(.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])))
        let opsB = try b.applyLocal(.addThemeAxis(EditOperation.AddThemeAxis(name: "density", options: ["compact", "normal"])))

        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        #expect(a.themes?["mode"] != nil)
        #expect(a.themes?["density"] != nil)
        assertConverged(a, b)
    }
}
