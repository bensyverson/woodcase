//
//  PropertyReadCostTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What one property read and one schema lookup may cost: reading a path costs that
/// path, not the node's whole payload, and a type's schema table is built once.
///
/// Counted with ``CostCounter`` rather than timed, so the checks hold on a loaded
/// machine. `PropertyReadCostProbe` times the same reads on a big document.
struct PropertyReadCostTests {
    /// A board holding a hundred rectangles — the payload a whole-kind encode would drag
    /// along with every read of the board's own width.
    private static func board() -> PenNode {
        let leaves = (0 ..< 100).map { index in
            PenNode(
                id: "leaf\(index)",
                common: PenNodeCommon(name: "Leaf \(index)"),
                kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
            )
        }
        return PenNode(
            id: "board",
            common: PenNodeCommon(name: "Board", x: .literal(4), opacity: .literal(0.5)),
            kind: .frame(PenNode.FrameData(width: .fixed(320), gap: .literal(8), children: leaves))
        )
    }

    /// Runs `body` with a fresh counter installed and returns the counter.
    private static func counting(_ body: () throws -> Void) rethrows -> CostCounter {
        let counter = CostCounter()
        try CostCounter.$current.withValue(counter) { try body() }
        return counter
    }

    @Test("Reading one kind path encodes no payload")
    func kindReadEncodesNoPayload() throws {
        let board = Self.board()
        var width: AnyCodable = .null
        let counter = try Self.counting {
            width = try NodePropertyCodec.value(at: "kind.width", of: board)
        }
        #expect(width == .int(320))
        #expect(counter.count(of: .payloadEncode) == 0)
    }

    @Test("Reading one common path encodes no payload")
    func commonReadEncodesNoPayload() throws {
        let board = Self.board()
        var name: AnyCodable = .null
        let counter = try Self.counting {
            name = try NodePropertyCodec.value(at: "common.name", of: board)
        }
        #expect(name == .string("Board"))
        #expect(counter.count(of: .payloadEncode) == 0)
    }

    @Test("Reading every path of a board encodes no payload")
    func everyPathEncodesNoPayload() throws {
        let board = Self.board()
        let counter = try Self.counting {
            for path in NodePropertyCodec.paths(for: board) {
                _ = try NodePropertyCodec.value(at: path, of: board)
            }
        }
        #expect(counter.count(of: .payloadEncode) == 0)
    }

    @Test("Looking up schema rows builds each table at most once", arguments: PenNode.NodeType.allCases)
    func schemaTableBuiltOnce(type: PenNode.NodeType) {
        let paths = PenSchema.fields(for: type).map(\.path)
        let counter = Self.counting {
            for _ in 0 ..< 20 {
                for path in paths {
                    _ = PenSchema.field(path, for: type)
                }
                _ = PenSchema.fields(for: type)
                _ = PenSchema.table(for: type)
                _ = PenSchema.common
            }
        }
        #expect(counter.count(of: .schemaTable(type)) <= 1)
        #expect(counter.count(of: .schemaTable(nil)) <= 1)
    }
}
