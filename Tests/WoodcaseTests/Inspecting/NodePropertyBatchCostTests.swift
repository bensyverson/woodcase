//
//  NodePropertyBatchCostTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a batch write may cost: N keys of a node cost at most one pass over its `common`
/// payload and one over its `kind` payload, never one per key.
///
/// Counted with ``CostCounter`` rather than timed; `BoardScalePatchProbe` times a whole
/// board's scale.
struct NodePropertyBatchCostTests {
    /// A frame board holding a few rectangles.
    private static func board() -> PenNode {
        let leaves = (0 ..< 10).map { index in
            PenNode(
                id: "leaf\(index)", common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
            )
        }
        return PenNode(
            id: "board",
            common: PenNodeCommon(name: "Board", x: .literal(4)),
            kind: .frame(PenNode.FrameData(width: .fixed(320), gap: .literal(8), children: leaves))
        )
    }

    /// The keys a proportional scale writes to a stack.
    private static let scalePatch: [String: AnyCodable] = [
        "common.x": .int(6), "common.y": .int(9), "kind.width": .int(480), "kind.height": .int(300),
        "kind.gap": .int(12), "kind.padding": .int(6), "kind.cornerRadius": .int(3), "kind.strokeWidth": .int(2),
    ]

    /// Runs `body` with a fresh counter installed and returns the counter.
    private static func counting(_ body: () throws -> Void) rethrows -> CostCounter {
        let counter = CostCounter()
        try CostCounter.$current.withValue(counter) { try body() }
        return counter
    }

    @Test("Patching eight keys of a board overlays each payload once")
    func batchOverlaysEachPayloadOnce() throws {
        let board = Self.board()
        var patched = board
        let counter = try Self.counting {
            patched = try NodePropertyCodec.setting(Self.scalePatch, on: board)
        }
        #expect(counter.count(of: .payloadOverlay) == 2)
        #expect(counter.count(of: .payloadEncode) == 0)
        #expect(counter.count(of: .payloadDecode) == 0)
        #expect(try NodePropertyCodec.value(at: "kind.gap", of: patched) == .int(12))
        #expect(patched.kind.inlineChildrenIfPresent == board.kind.inlineChildrenIfPresent)
    }

    @Test("A document's patch of eight keys overlays each payload once")
    func patchedNodeOverlaysEachPayloadOnce() throws {
        let document = EditableDocument(from: PenDocument(children: [Self.board()]))
        let op = EditOperation.SetProperties(nodeID: "board", properties: Self.scalePatch)
        let counter = try Self.counting {
            _ = try document.patchedNode(for: op)
        }
        #expect(counter.count(of: .payloadOverlay) <= 2)
    }

    @Test("A single-key write still overlays its payload once")
    func singleWriteOverlaysOnce() throws {
        let counter = try Self.counting {
            _ = try NodePropertyCodec.setting(.int(5), at: "kind.width", on: Self.board())
        }
        #expect(counter.count(of: .payloadOverlay) == 1)
    }
}
