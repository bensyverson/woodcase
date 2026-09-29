//
//  PenMeshGrid.swift
//  Woodcase
//

import Foundation

/// A mesh gradient ready to tessellate: a validated `columns × rows` grid of vertices,
/// each with its position, all four handles and a color resolved.
///
/// Build one from a fill with ``init(_:)``, which applies Pen's rules for when a fill is
/// drawn at all, or directly with ``init(columns:rows:vertices:)``. Positions and handles
/// are in the node's unit space; the tessellator scales them to device pixels.
///
/// Each run of four neighboring vertices is one ``PenMeshPatch``, so a grid of one
/// column or one row has no patches and paints nothing.
public struct PenMeshGrid: Friendly {
    /// Creates a grid from its vertices.
    ///
    /// - Parameters:
    ///   - columns: The vertex count across; at least 1.
    ///   - rows: The vertex count down; at least 1.
    ///   - vertices: `columns × rows` vertices, row-major.
    /// - Throws: ``Invalidity/nonPositiveDimension(columns:rows:)`` or
    ///   ``Invalidity/countMismatch(expected:points:colors:)``.
    public init(columns: Int, rows: Int, vertices: [Vertex]) throws(Invalidity) {
        guard columns > 0, rows > 0 else {
            throw .nonPositiveDimension(columns: columns, rows: rows)
        }
        guard vertices.count == columns * rows else {
            throw .countMismatch(expected: columns * rows, points: vertices.count, colors: vertices.count)
        }
        self.columns = columns
        self.rows = rows
        self.vertices = vertices
    }

    /// The vertex count across.
    public let columns: Int

    /// The vertex count down.
    public let rows: Int

    /// Every vertex, row-major.
    public let vertices: [Vertex]

    /// The patch count across: one fewer than ``columns``.
    public var patchColumns: Int {
        max(columns - 1, 0)
    }

    /// The patch count down: one fewer than ``rows``.
    public var patchRows: Int {
        max(rows - 1, 0)
    }

    /// The vertex at a grid position.
    ///
    /// - Parameters:
    ///   - column: The vertex column, `0..<columns`.
    ///   - row: The vertex row, `0..<rows`.
    /// - Returns: The vertex.
    public func vertex(column: Int, row: Int) -> Vertex {
        vertices[row * columns + column]
    }

    /// The patch whose top-left corner is the vertex at `(column, row)`.
    ///
    /// - Parameters:
    ///   - column: The patch column, `0..<patchColumns`.
    ///   - row: The patch row, `0..<patchRows`.
    /// - Returns: The patch spanning that vertex and its right, lower and diagonal
    ///   neighbors.
    public func patch(column: Int, row: Int) -> PenMeshPatch {
        PenMeshPatch(
            topLeft: vertex(column: column, row: row),
            topRight: vertex(column: column + 1, row: row),
            bottomLeft: vertex(column: column, row: row + 1),
            bottomRight: vertex(column: column + 1, row: row + 1)
        )
    }

    /// One resolved vertex of the grid.
    public struct Vertex: Friendly {
        /// Creates a vertex.
        ///
        /// - Parameters:
        ///   - position: Where the vertex sits, in the node's unit space.
        ///   - handles: All four handles, relative to `position`.
        ///   - color: The vertex color.
        public init(position: PenMeshPoint.Vector, handles: PenMeshPoint.Handles, color: PenMeshColor) {
            self.position = position
            self.handles = handles
            self.color = color
        }

        /// Where the vertex sits, in the node's unit space.
        public var position: PenMeshPoint.Vector

        /// All four handles, relative to ``position``.
        public var handles: PenMeshPoint.Handles

        /// The vertex color.
        public var color: PenMeshColor
    }
}
