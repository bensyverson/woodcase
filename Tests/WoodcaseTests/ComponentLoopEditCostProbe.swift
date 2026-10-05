//
//  ComponentLoopEditCostProbe.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What one local edit costs through a session on a 2,580-node, 30-component document —
/// a property nudge and a plain-rectangle insert, on the page and inside a component,
/// each alone and followed by one instance's expansion, then inside a component with the
/// document's layout cache primed — printed as `PROBE` lines.
///
/// A measurement, not a check: it runs only when asked, in a release build, and its
/// figures mean something only beside `uptime`:
///
/// ```sh
/// WOODCASE_LOOP_COST_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter ComponentLoopEditCostProbe
/// ```
@MainActor
struct ComponentLoopEditCostProbe {
    /// A node named by its id.
    static func node(_ id: String, _ kind: PenNode.Kind, reusable: Bool = false) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(name: id, reusable: reusable ? true : nil), kind: kind)
    }

    /// Thirty components of 25 nodes, each nesting the one before, and a page of 60
    /// boards holding eight instances and 21 plain nodes each.
    static func document() -> PenDocument {
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
    static func measure(_ label: String, _ session: DocumentSession, _ make: (Int) -> EditOperation, readBack: Bool) throws {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for i in 0 ..< 40 {
            let op = make(i)
            try samples.append(clock.measure {
                try session.submit(.local(LocalEdit(operations: [op])))
                if readBack { _ = try session.document.expandRef(nodeID: "B0i0") }
            })
        }
        samples.sort()
        let ms = { (d: Duration) in Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000 }
        print(String(format: "PROBE %@ median %.3f ms p90 %.3f ms", label, ms(samples[20]), ms(samples[36])))
    }

    @Test(
        "Edit cost on a 2,580-node, 30-component document",
        .enabled(if: ProcessInfo.processInfo.environment["WOODCASE_LOOP_COST_PROBE"] != nil)
    )
    func probe() throws {
        let author = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        let session = DocumentSession(document: Self.document(), author: author)
        print("PROBE nodes \(session.document.nodes.count) components \(session.document.componentRegistry.count)")
        for readBack in [false, true] {
            let tag = readBack ? "+expandRef" : ""
            try Self.measure("set x on page rect\(tag)", session, { i in
                .setProperties(EditOperation.SetProperties(nodeID: "B5r1l0", properties: ["common.x": .int(i)]))
            }, readBack: readBack)
            try Self.measure("set x in component\(tag)", session, { i in
                .setProperties(EditOperation.SetProperties(nodeID: "C5k1l0", properties: ["common.x": .int(i)]))
            }, readBack: readBack)
            try Self.measure("insert rect on page\(tag)", session, { i in
                .insertNode(EditOperation.InsertNode(node: Self.node("NP\(tag)\(i)", .rectangle(PenNode.RectangleData())), parentID: "B7r2"))
            }, readBack: readBack)
            try Self.measure("insert rect in component\(tag)", session, { i in
                .insertNode(EditOperation.InsertNode(node: Self.node("NC\(tag)\(i)", .rectangle(PenNode.RectangleData())), parentID: "C7k2"))
            }, readBack: readBack)
        }
        // A host that keeps the document's layout cache — Penumbra primes it — has each
        // structural edit work out which boards it changes.
        session.document.primeLayoutCache(with: [:])
        try Self.measure("set x in component, layout primed", session, { i in
            .setProperties(EditOperation.SetProperties(nodeID: "C5k1l0", properties: ["common.x": .int(1000 + i)]))
        }, readBack: false)
        try Self.measure("insert rect in component, layout primed", session, { i in
            .insertNode(EditOperation.InsertNode(node: Self.node("NL\(i)", .rectangle(PenNode.RectangleData())), parentID: "C7k2"))
        }, readBack: false)
    }
}
