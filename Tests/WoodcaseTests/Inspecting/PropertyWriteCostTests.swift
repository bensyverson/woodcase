//
//  PropertyWriteCostTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What one property write may cost: writing a path costs that path, not the node's
/// whole payload — a board's width is written without encoding or decoding its children.
///
/// Counted with ``CostCounter`` rather than timed, so the checks hold on a loaded
/// machine. `PropertyWriteCostProbe` times the same writes on a big document.
struct PropertyWriteCostTests {
    /// A hundred rectangles — the subtree a whole-payload write would drag along.
    private static let leaves: [PenNode] = (0 ..< 100).map { index in
        PenNode(
            id: "leaf\(index)",
            common: PenNodeCommon(name: "Leaf \(index)"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
        )
    }

    /// A frame board holding ``leaves``.
    private static func board() -> PenNode {
        PenNode(
            id: "board",
            common: PenNodeCommon(name: "Board", x: .literal(4), opacity: .literal(0.5)),
            kind: .frame(PenNode.FrameData(width: .fixed(320), gap: .literal(8), children: leaves))
        )
    }

    /// A group holding ``leaves``.
    private static func group() -> PenNode {
        PenNode(
            id: "group",
            common: PenNodeCommon(name: "Group"),
            kind: .group(PenNode.GroupData(children: leaves))
        )
    }

    /// Runs `body` with a fresh counter installed and returns the counter.
    private static func counting(_ body: () throws -> Void) rethrows -> CostCounter {
        let counter = CostCounter()
        try CostCounter.$current.withValue(counter) { try body() }
        return counter
    }

    /// Whether `counter` saw no payload go through JSON either way.
    private static func touchedNoJSON(_ counter: CostCounter) -> Bool {
        counter.count(of: .payloadEncode) == 0 && counter.count(of: .payloadDecode) == 0
    }

    @Test("Writing one kind path of a board encodes and decodes no payload")
    func kindWriteTouchesNoPayload() throws {
        let board = Self.board()
        var patched = board
        let counter = try Self.counting {
            patched = try NodePropertyCodec.setting(.int(500), at: "kind.width", on: board)
        }
        #expect(try NodePropertyCodec.value(at: "kind.width", of: patched) == .int(500))
        #expect(patched.kind.inlineChildrenIfPresent == Self.leaves)
        #expect(Self.touchedNoJSON(counter))
    }

    @Test("Clearing one kind path of a board encodes and decodes no payload")
    func kindClearTouchesNoPayload() throws {
        let board = Self.board()
        var patched = board
        let counter = try Self.counting {
            patched = try NodePropertyCodec.setting(.null, at: "kind.gap", on: board)
        }
        #expect(try NodePropertyCodec.value(at: "kind.gap", of: patched) == .null)
        #expect(try NodePropertyCodec.value(at: "kind.width", of: patched) == .int(320))
        #expect(Self.touchedNoJSON(counter))
    }

    @Test("Writing one kind path of a group encodes and decodes no payload")
    func groupWriteTouchesNoPayload() throws {
        let group = Self.group()
        var patched = group
        let counter = try Self.counting {
            patched = try NodePropertyCodec.setting(.string("multiply"), at: "kind.blendMode", on: group)
        }
        #expect(try NodePropertyCodec.value(at: "kind.blendMode", of: patched) == .string("multiply"))
        #expect(patched.kind.inlineChildrenIfPresent == Self.leaves)
        #expect(Self.touchedNoJSON(counter))
    }

    @Test("Writing one common path encodes and decodes no payload")
    func commonWriteTouchesNoPayload() throws {
        let board = Self.board()
        var patched = board
        let counter = try Self.counting {
            patched = try NodePropertyCodec.setting(.string("Renamed"), at: "common.name", on: board)
        }
        #expect(patched.common.name == "Renamed")
        #expect(patched.common.opacity == .literal(0.5))
        #expect(Self.touchedNoJSON(counter))
    }

    @Test("A refused write to a board encodes and decodes no payload")
    func refusedWriteTouchesNoPayload() {
        let board = Self.board()
        let counter = Self.counting {
            #expect(throws: EditingError.self) {
                try NodePropertyCodec.setting(.array([.bool(true)]), at: "kind.width", on: board)
            }
        }
        #expect(Self.touchedNoJSON(counter))
    }
}
