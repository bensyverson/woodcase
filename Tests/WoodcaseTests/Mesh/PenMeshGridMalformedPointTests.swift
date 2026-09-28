//
//  PenMeshGridMalformedPointTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the mesh core builds a grid around a ``PenMeshPoint/malformed(_:)`` point: where
/// Pen can place it, the vertex sits there; where Pen cannot, the fill is not drawn.
struct PenMeshGridMalformedPointTests {
    typealias Vector = PenMeshPoint.Vector
    typealias Fill = PenFill.PenMeshGradientFill

    private static let colors: [PenValue<String>] = [
        .literal("#FF0000"), .literal("#00FF00"), .literal("#0000FF"),
        .literal("#FFFF00"), .literal("#00FFFF"), .literal("#FF00FF"),
    ]

    /// A 3×2 fill whose vertex `index` is `point` and every other vertex sits on its grid position.
    private func fill(_ point: PenMeshPoint, at index: Int) -> Fill {
        var points: [PenMeshPoint] = (0 ..< 6).map {
            .bare(PenMeshPoint.gridPosition(column: $0 % 3, row: $0 / 3, columns: 3, rows: 2))
        }
        points[index] = point
        return Fill(columns: 3, rows: 2, colors: Self.colors, points: points)
    }

    @Test("A point Pen repairs sits on its grid position with default handles")
    func repairedPointSitsOnGrid() throws {
        let grid = try PenMeshGrid(fill(.malformed("oops"), at: 4))
        #expect(grid.vertices[4].position == Vector(0.5, 1))
        #expect(grid.vertices[4].handles == PenMeshPoint.Handles.defaults(columns: 3, rows: 2))
    }

    @Test("A longer array is placed at its first two numbers")
    func longArrayIsPlaced() throws {
        let grid = try PenMeshGrid(fill(.malformed([0.3, 0.2, 9]), at: 1))
        #expect(grid.vertices[1].position == Vector(0.3, 0.2))
    }

    @Test("A point Pen cannot place leaves the whole fill undrawn, naming the vertex")
    func unplaceablePointIsInvalid() {
        #expect(throws: PenMeshGrid.Invalidity.unplaceablePoint(index: 1)) {
            try PenMeshGrid(fill(.malformed([1]), at: 1))
        }
    }

    @Test("A count mismatch is still reported before an unplaceable point")
    func countMismatchComesFirst() {
        var mesh = fill(.malformed([1]), at: 1)
        mesh.points?.removeLast()
        #expect(throws: PenMeshGrid.Invalidity.countMismatch(expected: 6, points: 5, colors: 6)) {
            try PenMeshGrid(mesh)
        }
    }
}
