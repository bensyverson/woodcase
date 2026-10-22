//
//  ComponentLoopEditCostBench.swift
//  WoodcaseBench
//

import Foundation
import Woodcase

/// What one local edit costs through a session on a 2,580-node, 30-component document:
/// a property nudge and a plain-rectangle insert, on the page and inside a component,
/// each alone and followed by one instance's expansion, then inside a component with the
/// document's layout cache primed.
enum ComponentLoopEditCostBench {
    /// The bench.
    static let bench = Bench(
        name: "component-loop-edit-cost",
        summary: "Local edits through a session on a 2,580-node, 30-component document",
        run: { _ in try run() }
    )

    /// A node named by its id.
    private static func node(_ id: String, _ kind: PenNode.Kind, reusable: Bool = false) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id, reusable: reusable ? true : nil), kind: kind)
    }

    /// Thirty components of 25 nodes, each nesting the one before, and a page of 60
    /// boards holding eight instances and 21 plain nodes each.
    private static func document() -> PenDocument {
        var roots: [PenNode] = []
        for c in 0 ..< 30 {
            var kids: [PenNode] = []
            for k in 0 ..< 6 {
                let leaves = (0 ..< 3).map { node("C\(c)k\(k)l\($0)", .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))) }
                kids.append(node("C\(c)k\(k)", .frame(PenNode.FrameData(children: leaves))))
            }
            if c > 0 { kids.append(node("C\(c)nest", .ref(PenNode.RefData(ref: "C\(c - 1)")))) }
            roots.append(node("C\(c)", .frame(PenNode.FrameData(children: kids)), reusable: true))
        }
        var boards: [PenNode] = []
        for b in 0 ..< 60 {
            var kids: [PenNode] = []
            for i in 0 ..< 8 {
                kids.append(node("B\(b)i\(i)", .ref(PenNode.RefData(ref: "C\((b + i) % 30)"))))
            }
            for r in 0 ..< 7 {
                let leaves = (0 ..< 2).map { node("B\(b)r\(r)l\($0)", .rectangle(PenNode.RectangleData(width: .fixed(5), height: .fixed(5)))) }
                kids.append(node("B\(b)r\(r)", .frame(PenNode.FrameData(children: leaves))))
            }
            boards.append(node("B\(b)", .frame(PenNode.FrameData(children: kids))))
        }
        roots.append(node("Page", .frame(PenNode.FrameData(children: boards))))
        return PenDocument(children: roots)
    }

    /// Times forty submits of `make`'s edits and prints the median and p90.
    private static func measure(
        _ label: String, _ session: DocumentSession, _ make: (Int) -> EditOperation, readBack: Bool
    ) throws {
        var edit = 0
        try BenchClock.measure(label, runs: 40) {
            let op = make(edit)
            edit += 1
            try session.submit(.local(LocalEdit(operations: [op])))
            if readBack { _ = try session.document.expandRef(nodeID: "B0i0") }
        }
    }

    private static func run() throws {
        let author = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        let session = DocumentSession(document: document(), author: author)
        print("PROBE nodes \(session.document.nodes.count) components \(session.document.componentRegistry.count)")
        for readBack in [false, true] {
            let tag = readBack ? "+expandRef" : ""
            try measure("set x on page rect\(tag)", session, { i in
                .setProperties(EditOperation.SetProperties(nodeID: "B5r1l0", properties: ["common.x": .int(i)]))
            }, readBack: readBack)
            try measure("set x in component\(tag)", session, { i in
                .setProperties(EditOperation.SetProperties(nodeID: "C5k1l0", properties: ["common.x": .int(i)]))
            }, readBack: readBack)
            try measure("insert rect on page\(tag)", session, { i in
                .insertNode(EditOperation.InsertNode(node: node("NP\(tag)\(i)", .rectangle(PenNode.RectangleData())), parentID: "B7r2"))
            }, readBack: readBack)
            try measure("insert rect in component\(tag)", session, { i in
                .insertNode(EditOperation.InsertNode(node: node("NC\(tag)\(i)", .rectangle(PenNode.RectangleData())), parentID: "C7k2"))
            }, readBack: readBack)
        }
        // A host that keeps the document's layout cache — Penumbra primes it — has each
        // structural edit work out which boards it changes.
        session.document.primeLayoutCache(with: [:])
        try measure("set x in component, layout primed", session, { i in
            .setProperties(EditOperation.SetProperties(nodeID: "C5k1l0", properties: ["common.x": .int(1000 + i)]))
        }, readBack: false)
        try measure("insert rect in component, layout primed", session, { i in
            .insertNode(EditOperation.InsertNode(node: node("NL\(i)", .rectangle(PenNode.RectangleData())), parentID: "C7k2"))
        }, readBack: false)
    }
}
