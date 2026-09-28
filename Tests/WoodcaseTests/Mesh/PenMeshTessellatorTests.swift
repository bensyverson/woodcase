//
//  PenMeshTessellatorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The lattice the tessellator builds, and the error bound it promises.
struct PenMeshTessellatorTests {
    typealias Support = MeshTestSupport

    private let tessellator = PenMeshTessellator()

    /// A 3×3 mesh whose middle vertex is pulled off-centre with long handles, like the
    /// report's `mwarp` artboard.
    private func warped() throws -> PenMeshGrid {
        let navy = PenMeshColor(red: 0.12, green: 0.23, blue: 0.54)
        let pink = PenMeshColor(red: 0.96, green: 0.45, blue: 0.71)
        let base = try Support.regularGrid(columns: 3, rows: 3, colors: [navy, navy, navy, navy, pink, navy, Support.yellow, navy, Support.green])
        var vertices = base.vertices
        vertices[4].position = PenMeshPoint.Vector(0.3, 0.7)
        vertices[4].handles = PenMeshPoint.Handles(
            left: PenMeshPoint.Vector(-0.2, 0.1),
            right: PenMeshPoint.Vector(0.2, -0.1),
            top: PenMeshPoint.Vector(0.05, -0.3),
            bottom: PenMeshPoint.Vector(-0.05, 0.3)
        )
        return try PenMeshGrid(columns: 3, rows: 3, vertices: vertices)
    }

    @Test("A grid without patches tessellates to nothing")
    func empty() throws {
        let grid = try Support.regularGrid(columns: 2, rows: 1, colors: [Support.red, Support.green])
        #expect(tessellator.tessellate(grid, width: 100, height: 100) == .empty)
    }

    @Test("The lattice has one vertex per cell corner and two triangles per cell")
    func latticeCounts() throws {
        let grid = try warped()
        let mesh = tessellator.tessellate(grid, width: 240, height: 240)
        let across = mesh.columnSubdivisions.reduce(0, +)
        let down = mesh.rowSubdivisions.reduce(0, +)
        #expect(mesh.columnSubdivisions.count == 2)
        #expect(mesh.rowSubdivisions.count == 2)
        #expect(across > 2 && down > 2)
        #expect(mesh.positions.count == (across + 1) * (down + 1))
        #expect(mesh.colors.count == mesh.positions.count)
        #expect(mesh.triangleCount == 2 * across * down)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
    }

    @Test("Every lattice vertex is its patch evaluated at the cell corner, scaled to the box")
    func verticesAreEvaluatedPatchPoints() throws {
        let grid = try warped()
        let width = 300.0
        let height = 200.0
        let mesh = tessellator.tessellate(grid, width: width, height: height)
        var j = 0
        for (row, rowCells) in mesh.rowSubdivisions.enumerated() {
            for cellRow in 0 ... rowCells where cellRow < rowCells || row == mesh.rowSubdivisions.count - 1 {
                var i = 0
                for (column, columnCells) in mesh.columnSubdivisions.enumerated() {
                    for cellColumn in 0 ... columnCells where cellColumn < columnCells || column == mesh.columnSubdivisions.count - 1 {
                        let patch = grid.patch(column: column, row: row)
                        let u = Double(cellColumn) / Double(columnCells)
                        let v = Double(cellRow) / Double(rowCells)
                        let expected = patch.position(u: u, v: v)
                        let index = j * mesh.latticeColumns + i
                        #expect(abs(mesh.positions[index].x - expected.x * width) < 1e-9)
                        #expect(abs(mesh.positions[index].y - expected.y * height) < 1e-9)
                        #expect(mesh.colors[index] == patch.color(u: u, v: v))
                        i += 1
                    }
                }
                j += 1
            }
        }
    }

    @Test("A seam vertex is where both the patch above and the patch below put it")
    func seamsAgree() throws {
        let grid = try warped()
        let mesh = tessellator.tessellate(grid, width: 240, height: 240)
        let seamRow = mesh.rowSubdivisions[0]
        let cells = mesh.columnSubdivisions[0]
        let upper = grid.patch(column: 0, row: 0)
        let lower = grid.patch(column: 0, row: 1)
        for i in 0 ... cells {
            let u = Double(i) / Double(cells)
            let vertex = mesh.positions[seamRow * mesh.latticeColumns + i]
            for patch in [upper, lower] {
                let expected = patch.position(u: u, v: patch == upper ? 1 : 0)
                #expect(abs(vertex.x - expected.x * 240) < 1e-9)
                #expect(abs(vertex.y - expected.y * 240) < 1e-9)
            }
        }
    }

    @Test("A flat, single-colour mesh with straight handles needs one cell per patch")
    func flatNeedsOneCell() throws {
        let grid = try Support.regularGrid(
            columns: 3,
            rows: 2,
            handles: Support.thirdHandles(columns: 3, rows: 2),
            colors: Array(repeating: Support.blue, count: 6)
        )
        let mesh = tessellator.tessellate(grid, width: 4000, height: 4000)
        #expect(mesh.columnSubdivisions == [1, 1])
        #expect(mesh.rowSubdivisions == [1])
    }

    @Test("Geometric subdivision grows with the device size")
    func adaptiveToSize() throws {
        let grid = try Support.regularGrid(columns: 2, rows: 2, colors: Array(repeating: Support.blue, count: 4))
        let patch = grid.patch(column: 0, row: 0)
        let small = tessellator.subdivision(for: patch, width: 50, height: 50)
        let large = tessellator.subdivision(for: patch, width: 2000, height: 2000)
        #expect(small.u >= 1 && small.v >= 1)
        #expect(large.u > small.u)
        #expect(large.v > small.v)
    }

    @Test("Colour contrast asks for cells even when the geometry is flat")
    func colorNeedsCells() throws {
        let grid = try Support.fourColor(handles: Support.thirdHandles(columns: 2, rows: 2))
        let subdivision = tessellator.subdivision(for: grid.patch(column: 0, row: 0), width: 10, height: 10)
        #expect(subdivision.u > 8)
        #expect(subdivision.v > 8)
    }

    @Test("Subdivision is capped for absurd handles")
    func capped() throws {
        var grid = try Support.fourColor()
        var vertices = grid.vertices
        vertices[0].handles.right = PenMeshPoint.Vector(1e9, 1e9)
        grid = try PenMeshGrid(columns: 2, rows: 2, vertices: vertices)
        let subdivision = PenMeshTessellator(maximumSubdivisions: 64).subdivision(for: grid.patch(column: 0, row: 0), width: 100, height: 100)
        #expect(subdivision.u == 64)
    }

    @Test("Between vertices the triangles stay within both tolerances", arguments: [60.0, 240.0, 1200.0])
    func errorBound(size: Double) throws {
        for grid in try [warped(), Support.curved(), Support.fourColor()] {
            let mesh = tessellator.tessellate(grid, width: size, height: size)
            try assertWithinTolerance(mesh, grid: grid, size: size)
        }
    }

    /// Checks the midpoint of every cell's diagonal, the point a triangle interpolates
    /// furthest from its vertices along the edge both triangles share.
    private func assertWithinTolerance(_ mesh: PenMeshTessellation, grid: PenMeshGrid, size: Double) throws {
        var worstPosition = 0.0
        var worstColor = 0.0
        for (row, rowCells) in mesh.rowSubdivisions.enumerated() {
            for (column, columnCells) in mesh.columnSubdivisions.enumerated() {
                let patch = grid.patch(column: column, row: row)
                for cellRow in 0 ..< rowCells {
                    for cellColumn in 0 ..< columnCells {
                        let u0 = Double(cellColumn) / Double(columnCells)
                        let u1 = Double(cellColumn + 1) / Double(columnCells)
                        let v0 = Double(cellRow) / Double(rowCells)
                        let v1 = Double(cellRow + 1) / Double(rowCells)
                        let a = patch.position(u: u0, v: v0)
                        let b = patch.position(u: u1, v: v1)
                        let mid = patch.position(u: (u0 + u1) / 2, v: (v0 + v1) / 2)
                        let dx = (a.x + b.x) / 2 * size - mid.x * size
                        let dy = (a.y + b.y) / 2 * size - mid.y * size
                        worstPosition = max(worstPosition, (dx * dx + dy * dy).squareRoot())
                        let ca = premultiplied(patch.color(u: u0, v: v0))
                        let cb = premultiplied(patch.color(u: u1, v: v1))
                        let cm = premultiplied(patch.color(u: (u0 + u1) / 2, v: (v0 + v1) / 2))
                        for channel in 0 ..< 4 {
                            worstColor = max(worstColor, abs((ca[channel] + cb[channel]) / 2 - cm[channel]))
                        }
                    }
                }
            }
        }
        #expect(worstPosition <= tessellator.geometricTolerance)
        #expect(worstColor <= tessellator.colorTolerance)
    }

    private func premultiplied(_ color: PenMeshColor) -> [Double] {
        [color.red * color.alpha, color.green * color.alpha, color.blue * color.alpha, color.alpha]
    }
}
