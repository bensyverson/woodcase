//
//  CRDTKindPropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct CRDTKindPropertyTests {
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

    private func makeRectDoc() -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(50)))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [rect]))
        )
        return PenDocument(children: [frame])
    }

    private func makeTextDoc() -> PenDocument {
        let text = PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Text"),
            kind: .text(PenNode.TextData(
                width: .fixed(200),
                fontFamily: .literal("Inter"),
                fontSize: .literal(16)
            ))
        )
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), children: [text]))
        )
        return PenDocument(children: [frame])
    }

    private func makeFrameDoc() -> PenDocument {
        let frame = PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Frame"),
            kind: .frame(PenNode.FrameData(
                width: .fixed(400),
                layout: .horizontal,
                gap: .literal(8),
                padding: .uniform(.literal(16))
            ))
        )
        return PenDocument(children: [frame])
    }

    // MARK: - Tests

    @Test("Remote kind property applied: rectangle width")
    func remoteKindPropertyApplied_rectangle() throws {
        let (a, b) = makePair(from: makeRectDoc())

        // Peer A changes rect width to 200
        let newKind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200), height: .fixed(50)
        ))
        let opsA = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: newKind
        )))

        // Send to B
        sync(a, to: b, ops: opsA)

        // B should have the updated width
        if case let .rectangle(data) = b.nodes["r1"]?.kind {
            #expect(data.width == .fixed(200), "B should have A's updated width")
        } else {
            Issue.record("r1 should still be a rectangle")
        }
        assertConverged(a, b)
    }

    @Test("Kind property convergence: different fields on same node")
    func kindPropertyConvergence_differentFields() throws {
        let (a, b) = makePair(from: makeRectDoc())

        // A changes width
        let kindA = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200), height: .fixed(50)
        ))
        let opsA = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: kindA
        )))

        // B changes fills
        let fills = PenFills.single(PenFill.shorthand("#FF0000"))
        let kindB = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(100), height: .fixed(50), fills: fills
        ))
        let opsB = try b.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: kindB
        )))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should have A's width AND B's fills
        if case let .rectangle(dataA) = a.nodes["r1"]?.kind,
           case let .rectangle(dataB) = b.nodes["r1"]?.kind
        {
            #expect(dataA.width == .fixed(200), "A should have updated width")
            #expect(dataA.fills == fills, "A should have B's fills")
            #expect(dataB.width == .fixed(200), "B should have A's width")
            #expect(dataB.fills == fills, "B should have B's fills")
        } else {
            Issue.record("r1 should still be a rectangle on both peers")
        }
        assertConverged(a, b)
    }

    @Test("Kind property convergence: same field LWW")
    func kindPropertyConvergence_sameField_LWW() throws {
        let (a, b) = makePair(from: makeRectDoc())

        // Both change width
        let kindA = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200), height: .fixed(50)
        ))
        let opsA = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: kindA
        )))

        let kindB = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(300), height: .fixed(50)
        ))
        let opsB = try b.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: kindB
        )))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should converge to the same width (LWW winner)
        if case let .rectangle(dataA) = a.nodes["r1"]?.kind,
           case let .rectangle(dataB) = b.nodes["r1"]?.kind
        {
            #expect(dataA.width == dataB.width, "Both peers should converge on the same width")
        } else {
            Issue.record("r1 should still be a rectangle on both peers")
        }
        assertConverged(a, b)
    }

    @Test("Kind property convergence: text data fields")
    func kindPropertyConvergence_textData() throws {
        let (a, b) = makePair(from: makeTextDoc())

        // A changes fontSize
        let kindA = PenNode.Kind.text(PenNode.TextData(
            width: .fixed(200), fontFamily: .literal("Inter"), fontSize: .literal(24)
        ))
        let opsA = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "t1", kind: kindA
        )))

        // B changes fontFamily
        let kindB = PenNode.Kind.text(PenNode.TextData(
            width: .fixed(200), fontFamily: .literal("Roboto"), fontSize: .literal(16)
        ))
        let opsB = try b.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "t1", kind: kindB
        )))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // Both should have A's fontSize AND B's fontFamily
        if case let .text(dataA) = a.nodes["t1"]?.kind,
           case let .text(dataB) = b.nodes["t1"]?.kind
        {
            #expect(dataA.fontSize == .literal(24), "A should have A's fontSize")
            #expect(dataA.fontFamily == .literal("Roboto"), "A should have B's fontFamily")
            #expect(dataB.fontSize == .literal(24), "B should have A's fontSize")
            #expect(dataB.fontFamily == .literal("Roboto"), "B should have B's fontFamily")
        } else {
            Issue.record("t1 should still be text on both peers")
        }
        assertConverged(a, b)
    }

    @Test("Kind property convergence: frame layout fields")
    func kindPropertyConvergence_frameData() throws {
        let (a, b) = makePair(from: makeFrameDoc())

        // A changes layout to vertical
        let kindA = PenNode.Kind.frame(PenNode.FrameData(
            width: .fixed(400),
            layout: .vertical,
            gap: .literal(8),
            padding: .uniform(.literal(16))
        ))
        let opsA = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "f1", kind: kindA
        )))

        // B changes gap and padding
        let kindB = PenNode.Kind.frame(PenNode.FrameData(
            width: .fixed(400),
            layout: .horizontal,
            gap: .literal(16),
            padding: .uniform(.literal(24))
        ))
        let opsB = try b.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "f1", kind: kindB
        )))

        // Exchange
        sync(a, to: b, ops: opsA)
        sync(b, to: a, ops: opsB)

        // A's layout, B's gap and padding should win
        if case let .frame(dataA) = a.nodes["f1"]?.kind,
           case let .frame(dataB) = b.nodes["f1"]?.kind
        {
            #expect(dataA.layout == dataB.layout, "layout should converge")
            #expect(dataA.gap == dataB.gap, "gap should converge")
            #expect(dataA.padding == dataB.padding, "padding should converge")
        } else {
            Issue.record("f1 should still be a frame on both peers")
        }
        assertConverged(a, b)
    }

    @Test("extractKindValue returns real values, not stub strings")
    func extractKindValue_notStub() throws {
        let (a, _) = makePair(from: makeRectDoc())

        // Change width on the rectangle
        let newKind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(200), height: .fixed(50)
        ))
        let ops = try a.applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: "r1", kind: newKind
        )))

        // The emitted ops should have real values, not the stub's .string(property) return
        for op in ops {
            if case let .setProperty(p) = op.payload, p.property == "kind.width" {
                // The stub returns .string("kind.width") — a real implementation
                // returns an encoded PenSizing value
                #expect(p.value != .string("kind.width"), "extractKindValue should not return the stub value")
                return
            }
        }
        Issue.record("Expected a setProperty op for kind.width")
    }

    @Test("common.theme round-trips through CRDT")
    func commonThemePropertyRoundTrip() throws {
        let (a, b) = makePair(from: makeRectDoc())

        // A sets theme on r1
        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(
                name: "Rect",
                opacity: .literal(1.0),
                theme: ["mode": "dark"]
            )
        )))

        // Send to B
        sync(a, to: b, ops: opsA)

        // B should have the theme
        #expect(b.nodes["r1"]?.common.theme == ["mode": "dark"], "B should have A's theme")
        assertConverged(a, b)
    }

    @Test("common.metadata round-trips through CRDT")
    func commonMetadataPropertyRoundTrip() throws {
        let (a, b) = makePair(from: makeRectDoc())

        // A sets metadata on r1
        let opsA = try a.applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(
                name: "Rect",
                opacity: .literal(1.0),
                metadata: ["key": AnyCodable.string("value")]
            )
        )))

        // Send to B
        sync(a, to: b, ops: opsA)

        // B should have the metadata
        #expect(
            b.nodes["r1"]?.common.metadata == ["key": AnyCodable.string("value")],
            "B should have A's metadata"
        )
        assertConverged(a, b)
    }
}
