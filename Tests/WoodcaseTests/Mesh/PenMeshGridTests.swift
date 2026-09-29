//
//  PenMeshGridTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pen's rules for whether a mesh gradient fill is drawn, and how its vertices resolve.
struct PenMeshGridTests {
    typealias Vector = PenMeshPoint.Vector
    typealias Fill = PenFill.PenMeshGradientFill

    private func fill(
        columns: Int? = 2,
        rows: Int? = 2,
        colors: [PenValue<String>]? = [.literal("#FF0000"), .literal("#00FF00"), .literal("#0000FF"), .literal("#FFFF00")],
        points: [PenMeshPoint]? = [.bare(Vector(0, 0)), .bare(Vector(1, 0)), .bare(Vector(0, 1)), .bare(Vector(1, 1))]
    ) -> Fill {
        Fill(columns: columns, rows: rows, colors: colors, points: points)
    }

    private func invalidity(_ fill: Fill) -> PenMeshGrid.Invalidity? {
        do {
            _ = try PenMeshGrid(fill)
            return nil
        } catch {
            return error
        }
    }

    @Test("A complete fill builds a grid with the fill's positions and colors")
    func complete() throws {
        let grid = try PenMeshGrid(fill())
        #expect(grid.columns == 2)
        #expect(grid.rows == 2)
        #expect(grid.vertices.map(\.position) == [Vector(0, 0), Vector(1, 0), Vector(0, 1), Vector(1, 1)])
        #expect(grid.vertices.map(\.color) == [MeshTestSupport.red, MeshTestSupport.green, MeshTestSupport.blue, MeshTestSupport.yellow])
    }

    @Test("A bare point takes the grid's default handles; an object point keeps the ones it names")
    func handles() throws {
        let named = Vector(0.2, 0.1)
        let points: [PenMeshPoint] = [
            .bare(Vector(0, 0)),
            .object(PenMeshPoint.Object(position: Vector(1, 0), bottomHandle: named)),
            .bare(Vector(0, 1)),
            .bare(Vector(1, 1)),
        ]
        let grid = try PenMeshGrid(fill(points: points))
        let defaults = PenMeshPoint.Handles.defaults(columns: 2, rows: 2)
        #expect(grid.vertices[0].handles == defaults)
        var expected = defaults
        expected.bottom = named
        #expect(grid.vertices[1].handles == expected)
    }

    @Test("An unresolved variable is opaque black; a color is read as Pen's mesh reads it")
    func unreadableColors() throws {
        let colors: [PenValue<String>] = [.variable("brand"), .literal("#1234"), .literal("red"), .literal("#FF000080")]
        let grid = try PenMeshGrid(fill(colors: colors))
        #expect(grid.vertices.map(\.color) == [
            .black, .transparent, PenMeshColor(red: 0, green: 238.0 / 255, blue: 221.0 / 255),
            PenMeshColor(red: 1, green: 0, blue: 0, alpha: 128.0 / 255),
        ])
    }

    @Test("A missing field drops the fill")
    func missingFields() {
        #expect(invalidity(fill(columns: nil)) == .missingColumns)
        #expect(invalidity(fill(rows: nil)) == .missingRows)
        #expect(invalidity(fill(points: nil)) == .missingPoints)
        #expect(invalidity(fill(colors: nil)) == .missingColors)
    }

    @Test("A count that is not columns × rows drops the fill")
    func countMismatch() {
        #expect(invalidity(fill(columns: 3)) == .countMismatch(expected: 6, points: 4, colors: 4))
        #expect(invalidity(fill(colors: [.literal("#000000")])) == .countMismatch(expected: 4, points: 4, colors: 1))
    }

    @Test("Zero or negative dimensions drop the fill")
    func nonPositive() {
        #expect(invalidity(fill(columns: 0, rows: 2, colors: [], points: [])) == .nonPositiveDimension(columns: 0, rows: 2))
        #expect(invalidity(fill(columns: -2, rows: -2)) == .nonPositiveDimension(columns: -2, rows: -2))
    }

    @Test("The vertex initializer validates the count too")
    func vertexInitializer() {
        let vertex = PenMeshGrid.Vertex(position: Vector(0, 0), handles: .defaults(columns: 2, rows: 2), color: .black)
        #expect(throws: PenMeshGrid.Invalidity.countMismatch(expected: 4, points: 1, colors: 1)) {
            try PenMeshGrid(columns: 2, rows: 2, vertices: [vertex])
        }
    }

    @Test("One column is a valid grid with no patches")
    func singleColumn() throws {
        let grid = try PenMeshGrid(fill(columns: 1, rows: 4))
        #expect(grid.patchColumns == 0)
        #expect(grid.patchRows == 3)
    }
}
