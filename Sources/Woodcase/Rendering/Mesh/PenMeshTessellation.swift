//
//  PenMeshTessellation.swift
//  Woodcase
//

import Foundation

/// A mesh gradient as plain triangles with per-vertex colors, in device pixels.
///
/// This is the vertex buffer a GPU draws with Gouraud shading, and what
/// ``PenMeshRasterizer`` draws on the CPU. Positions are measured from the top-left
/// corner of the node's box, `y` down, already scaled to the size given to
/// ``PenMeshTessellator/tessellate(_:width:height:)``.
///
/// The vertices form one lattice over the whole grid: patch column `c` owns
/// ``columnSubdivisions``[c] cells across and patch row `r` owns ``rowSubdivisions``[r]
/// cells down, so neighboring patches share every vertex along their common edge. The
/// mesh is therefore watertight by construction: no T-junctions, no cracks. Vertex
/// `(i, j)` of the lattice is at index `j * latticeColumns + i`.
///
/// Triangles are listed patch by patch in row-major order, then cell by cell within each
/// patch, two per cell split along the cell's top-left to bottom-right diagonal. That is
/// the order Pen paints a folded mesh in: a later patch covers an earlier one.
public struct PenMeshTessellation: Friendly {
    /// Creates a tessellation.
    ///
    /// - Parameters:
    ///   - positions: One position per vertex, in device pixels.
    ///   - colors: One unpremultiplied color per vertex.
    ///   - indices: Three vertex indices per triangle.
    ///   - columnSubdivisions: The cell count across each patch column.
    ///   - rowSubdivisions: The cell count down each patch row.
    public init(
        positions: [SIMD2<Double>],
        colors: [PenMeshColor],
        indices: [UInt32],
        columnSubdivisions: [Int],
        rowSubdivisions: [Int]
    ) {
        self.positions = positions
        self.colors = colors
        self.indices = indices
        self.columnSubdivisions = columnSubdivisions
        self.rowSubdivisions = rowSubdivisions
    }

    /// One position per vertex, in device pixels from the box's top-left corner.
    public var positions: [SIMD2<Double>]

    /// One unpremultiplied, sRGB-encoded color per vertex. Premultiply before
    /// interpolating, as ``PenMeshRasterizer`` does.
    public var colors: [PenMeshColor]

    /// Three indices into ``positions`` and ``colors`` per triangle.
    public var indices: [UInt32]

    /// The cell count across each patch column, left to right.
    public var columnSubdivisions: [Int]

    /// The cell count down each patch row, top to bottom.
    public var rowSubdivisions: [Int]

    /// The number of triangles.
    public var triangleCount: Int {
        indices.count / 3
    }

    /// The lattice's vertex count across: one more than the total cell count across.
    public var latticeColumns: Int {
        columnSubdivisions.reduce(0, +) + 1
    }

    /// A tessellation with nothing in it: what a grid without patches produces.
    public static let empty = PenMeshTessellation(
        positions: [],
        colors: [],
        indices: [],
        columnSubdivisions: [],
        rowSubdivisions: []
    )
}
