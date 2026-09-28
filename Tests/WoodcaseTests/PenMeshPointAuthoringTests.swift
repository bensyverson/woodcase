//
//  PenMeshPointAuthoringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An agent's `set` or `add` with a mesh fill refuses a malformed point, while the same
/// point read from a file is kept (``PenMeshPoint/malformed(_:)``).
struct PenMeshPointAuthoringTests {
    /// A 2×2 mesh fill with vertex 2 written as `point`.
    private func meshFill(point: AnyCodable) -> AnyCodable {
        [
            "type": "mesh_gradient", "columns": 2, "rows": 2,
            "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"],
            "points": [[0, 0], point, [0, 1], [1, 1]],
        ]
    }

    private func frame() -> PenNode {
        PenNode(id: "f1", common: PenNodeCommon(name: "Card"), kind: .frame(PenNode.FrameData()))
    }

    @Test("set refuses a mesh fill with a malformed point, naming the property")
    func setRefuses() {
        #expect {
            try NodePropertyCodec.checkAuthored(["kind.fills": meshFill(point: "oops")], on: frame())
        } throws: { error in
            guard case let EditingError.propertyTypeMismatch(nodeID, key, _, _) = error else { return false }
            return nodeID == "f1" && key == "kind.fills"
        }
    }

    @Test("set takes a mesh fill whose points are well formed")
    func setTakesWellFormed() throws {
        try NodePropertyCodec.checkAuthored(["kind.fills": meshFill(point: [1, 0])], on: frame())
    }

    @Test("add refuses a node whose mesh fill has a malformed point")
    func addRefuses() {
        #expect(throws: DecodingError.self) {
            _ = try PenSubtreeDecoder.node(from: [
                "type": "frame", "name": "Card", "fill": meshFill(point: [1]),
            ])
        }
    }

    @Test("A file decode of the same fill keeps the point")
    func fileKeeps() throws {
        let data = try JSONEncoder().encode(meshFill(point: [1]))
        let fill = try JSONDecoder().decode(PenFill.self, from: data)
        guard case let .meshGradient(mesh) = fill else {
            Issue.record("not a mesh fill")
            return
        }
        #expect(mesh.points?[1] == .malformed([1]))
    }
}
