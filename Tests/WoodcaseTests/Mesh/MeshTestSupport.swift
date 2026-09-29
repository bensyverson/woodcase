//
//  MeshTestSupport.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Builders shared by the mesh gradient suites.
enum MeshTestSupport {
    typealias Vector = PenMeshPoint.Vector

    static let red = PenMeshColor(red: 1, green: 0, blue: 0)
    static let green = PenMeshColor(red: 0, green: 1, blue: 0)
    static let blue = PenMeshColor(red: 0, green: 0, blue: 1)
    static let yellow = PenMeshColor(red: 1, green: 1, blue: 0)

    /// Handles a third of a cell long: with evenly spaced vertices these make every
    /// Bézier edge a uniformly parametrized straight line.
    static func thirdHandles(columns: Int, rows: Int) -> PenMeshPoint.Handles {
        let dx = 1.0 / 3 / Double(columns - 1)
        let dy = 1.0 / 3 / Double(rows - 1)
        return PenMeshPoint.Handles(left: Vector(-dx, 0), right: Vector(dx, 0), top: Vector(0, -dy), bottom: Vector(0, dy))
    }

    /// An evenly spaced grid over the unit square.
    ///
    /// - Parameters:
    ///   - handles: The handles every vertex takes; the grid defaults when `nil`.
    ///   - colors: One color per vertex, row-major.
    static func regularGrid(
        columns: Int,
        rows: Int,
        handles: PenMeshPoint.Handles? = nil,
        colors: [PenMeshColor]
    ) throws -> PenMeshGrid {
        let resolved = handles ?? PenMeshPoint.Handles.defaults(columns: columns, rows: rows)
        var vertices: [PenMeshGrid.Vertex] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let position = Vector(Double(column) / Double(columns - 1), Double(row) / Double(rows - 1))
                vertices.append(PenMeshGrid.Vertex(position: position, handles: resolved, color: colors[row * columns + column]))
            }
        }
        return try PenMeshGrid(columns: columns, rows: rows, vertices: vertices)
    }

    /// The 2×2 red/green/blue/yellow mesh of the report's `m2x2` artboard.
    static func fourColor(handles: PenMeshPoint.Handles? = nil) throws -> PenMeshGrid {
        try regularGrid(columns: 2, rows: 2, handles: handles, colors: [red, green, blue, yellow])
    }

    /// A 2×2 mesh whose top-left vertex has curved right and bottom handles.
    ///
    /// Expected points below were computed exactly, with rational arithmetic, from the
    /// control net this produces.
    static func curved() throws -> PenMeshGrid {
        let defaults = PenMeshPoint.Handles.defaults(columns: 2, rows: 2)
        var topLeft = defaults
        topLeft.right = Vector(1.0 / 3, 0.3)
        topLeft.bottom = Vector(0.1, 0.4)
        let vertices = [
            PenMeshGrid.Vertex(position: Vector(0, 0), handles: topLeft, color: red),
            PenMeshGrid.Vertex(position: Vector(1, 0), handles: defaults, color: green),
            PenMeshGrid.Vertex(position: Vector(0, 1), handles: defaults, color: blue),
            PenMeshGrid.Vertex(position: Vector(1, 1), handles: defaults, color: yellow),
        ]
        return try PenMeshGrid(columns: 2, rows: 2, vertices: vertices)
    }

    /// Smoothstep, written out independently of the code under test.
    static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    /// The bilinear blend of four colors at `(s, t)`.
    static func bilinear(_ tl: PenMeshColor, _ tr: PenMeshColor, _ bl: PenMeshColor, _ br: PenMeshColor, s: Double, t: Double) -> PenMeshColor {
        func mix(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            a * (1 - s) * (1 - t) + b * s * (1 - t) + c * (1 - s) * t + d * s * t
        }
        return PenMeshColor(
            red: mix(tl.red, tr.red, bl.red, br.red),
            green: mix(tl.green, tr.green, bl.green, br.green),
            blue: mix(tl.blue, tr.blue, bl.blue, br.blue),
            alpha: mix(tl.alpha, tr.alpha, bl.alpha, br.alpha)
        )
    }
}
