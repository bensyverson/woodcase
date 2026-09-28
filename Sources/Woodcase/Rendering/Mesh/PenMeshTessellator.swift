//
//  PenMeshTessellator.swift
//  Woodcase
//

import Foundation

/// Turns a ``PenMeshGrid`` into a ``PenMeshTessellation`` fine enough for the size it
/// will be drawn at.
///
/// Pen cuts every patch into a fixed 32 × 32 cells, whatever its size on screen, so a
/// large mesh shows its facets and a small one wastes triangles. This tessellator
/// instead chooses each patch's cell counts from a bound on how far the flat triangles
/// can stray from the true patch, and keeps that below two tolerances:
///
/// - ``geometricTolerance``, in device pixels: the largest distance between a point of
///   a triangle and the patch point it stands for. Its default, a quarter of a pixel, is
///   below what a pixel-centre sampler can show.
/// - ``colorTolerance``, in channel units (`1` is a full channel): the largest
///   difference between a premultiplied colour interpolated across a triangle and the
///   true one. Its default, half of one 8-bit step, means the interpolated colour rounds
///   to the exact colour's step or its neighbour.
///
/// The bound is the one for piecewise-linear interpolation of a smooth surface over a
/// triangulated grid (Filip, Magedson and Markot, 1986): with cell sizes `hᵤ`, `hᵥ`,
///
/// ```
/// error ≤ ⅛ (Mᵤᵤ hᵤ² + 2 Mᵤᵥ hᵤ hᵥ + Mᵥᵥ hᵥ²)
/// ```
///
/// where the `M`s bound the second derivatives over the patch. For the geometry they come
/// from the control net's second differences, scaled to device pixels; for the colour,
/// from the corner colours and smoothstep's derivatives. Since `2hᵤhᵥ ≤ hᵤ² + hᵥ²`, the
/// tessellator gives each axis half of the tolerance and solves for its cell count.
/// Geometry is the size-dependent part, so the count grows with the square root of the
/// patch's size in pixels; colour alone never asks for more than about 60 cells.
///
/// Every patch in a column shares the largest count any of them asks for across, and
/// every patch in a row the largest count down, so shared edges line up exactly.
public struct PenMeshTessellator: Friendly {
    /// Creates a tessellator.
    ///
    /// - Parameters:
    ///   - geometricTolerance: The largest position error, in device pixels.
    ///   - colorTolerance: The largest premultiplied colour error, in channel units.
    ///   - maximumSubdivisions: The most cells along one axis of one patch.
    public init(
        geometricTolerance: Double = 0.25,
        colorTolerance: Double = 0.5 / 255,
        maximumSubdivisions: Int = 512
    ) {
        self.geometricTolerance = geometricTolerance
        self.colorTolerance = colorTolerance
        self.maximumSubdivisions = maximumSubdivisions
    }

    /// The largest distance, in device pixels, between a triangle and the patch it
    /// approximates.
    public var geometricTolerance: Double

    /// The largest difference, in channel units, between an interpolated premultiplied
    /// colour and the patch's own.
    public var colorTolerance: Double

    /// The most cells along one axis of one patch: a guard against absurd handles, not a
    /// quality setting.
    public var maximumSubdivisions: Int

    /// Tessellates a grid for a box of the given size in device pixels.
    ///
    /// - Parameters:
    ///   - grid: The mesh.
    ///   - width: The node box's width in device pixels.
    ///   - height: The node box's height in device pixels.
    /// - Returns: The triangles, or ``PenMeshTessellation/empty`` for a grid without
    ///   patches.
    public func tessellate(_ grid: PenMeshGrid, width: Double, height: Double) -> PenMeshTessellation {
        guard grid.patchColumns > 0, grid.patchRows > 0 else { return .empty }
        let patches = (0 ..< grid.patchRows).map { row in
            (0 ..< grid.patchColumns).map { grid.patch(column: $0, row: row) }
        }
        let needs = patches.map { $0.map { subdivision(for: $0, width: width, height: height) } }
        let columnCells = (0 ..< grid.patchColumns).map { column in needs.map { $0[column].u }.max() ?? 1 }
        let rowCells = (0 ..< grid.patchRows).map { row in needs[row].map(\.v).max() ?? 1 }

        let across = Self.lattice(columnCells)
        let down = Self.lattice(rowCells)
        var positions: [SIMD2<Double>] = []
        var colors: [PenMeshColor] = []
        positions.reserveCapacity(across.count * down.count)
        colors.reserveCapacity(across.count * down.count)
        for (row, v) in down {
            for (column, u) in across {
                let patch = patches[row][column]
                let point = patch.position(u: u, v: v)
                positions.append(SIMD2(point.x * width, point.y * height))
                colors.append(patch.color(u: u, v: v))
            }
        }
        return PenMeshTessellation(
            positions: positions,
            colors: colors,
            indices: Self.triangles(columnCells: columnCells, rowCells: rowCells),
            columnSubdivisions: columnCells,
            rowSubdivisions: rowCells
        )
    }

    /// The patch and parameter of each lattice line along one axis.
    ///
    /// A line on the edge between two patches is evaluated in the later patch at
    /// parameter 0; the earlier patch would give the same point at parameter 1.
    private static func lattice(_ cells: [Int]) -> [(patch: Int, parameter: Double)] {
        var lines: [(patch: Int, parameter: Double)] = []
        for (patch, count) in cells.enumerated() {
            for cell in 0 ..< count {
                lines.append((patch, Double(cell) / Double(count)))
            }
        }
        lines.append((cells.count - 1, 1))
        return lines
    }

    /// Two triangles per cell, patch by patch in row-major order and cell by cell within
    /// each patch, so a later patch paints over an earlier one where a mesh folds.
    private static func triangles(columnCells: [Int], rowCells: [Int]) -> [UInt32] {
        let stride = columnCells.reduce(0, +) + 1
        let columnStarts = columnCells.reduce(into: [0]) { $0.append($0.last! + $1) }
        let rowStarts = rowCells.reduce(into: [0]) { $0.append($0.last! + $1) }
        var indices: [UInt32] = []
        indices.reserveCapacity(6 * (stride - 1) * rowStarts.last!)
        for row in rowCells.indices {
            for column in columnCells.indices {
                for j in rowStarts[row] ..< rowStarts[row + 1] {
                    for i in columnStarts[column] ..< columnStarts[column + 1] {
                        let topLeft = UInt32(j * stride + i)
                        let topRight = topLeft + 1
                        let bottomLeft = topLeft + UInt32(stride)
                        let bottomRight = bottomLeft + 1
                        indices += [topLeft, bottomRight, bottomLeft, topLeft, topRight, bottomRight]
                    }
                }
            }
        }
        return indices
    }
}
