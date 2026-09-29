//
//  PenMeshGrid+Fill.swift
//  Woodcase
//

import Foundation

public extension PenMeshGrid {
    /// Builds the grid a mesh gradient fill describes, or says why Pen would not draw it.
    ///
    /// Pass a fill whose colors the ``PenVariableResolver`` has already resolved. A
    /// color string is read as Pen's mesh reads it (``PenMeshColor/init(penMesh:)``): a
    /// malformed one is not black but whatever Pen makes of it, often transparent. A
    /// color that is still a variable becomes opaque black. A point that omits a handle takes
    /// the grid's default for it (``PenMeshPoint/Handles/defaults(columns:rows:)``). A
    /// malformed point sits where Pen places it
    /// (``PenMeshPoint/placement(gridPosition:defaults:)``).
    ///
    /// - Parameter fill: The fill, with resolved colors.
    /// - Throws: An ``Invalidity`` naming the first missing field, mismatched count or
    ///   point Pen cannot place.
    init(_ fill: PenFill.PenMeshGradientFill) throws(Invalidity) {
        guard let columns = fill.columns else { throw .missingColumns }
        guard let rows = fill.rows else { throw .missingRows }
        guard let points = fill.points else { throw .missingPoints }
        guard let colors = fill.colors else { throw .missingColors }
        guard columns > 0, rows > 0 else {
            throw .nonPositiveDimension(columns: columns, rows: rows)
        }
        guard points.count == columns * rows, colors.count == columns * rows else {
            throw .countMismatch(expected: columns * rows, points: points.count, colors: colors.count)
        }
        let defaults = PenMeshPoint.Handles.defaults(columns: columns, rows: rows)
        var vertices: [Vertex] = []
        vertices.reserveCapacity(points.count)
        for (index, (point, color)) in zip(points, colors).enumerated() {
            let gridPosition = PenMeshPoint.gridPosition(
                column: index % columns, row: index / columns, columns: columns, rows: rows
            )
            guard let placement = point.placement(gridPosition: gridPosition, defaults: defaults) else {
                throw .unplaceablePoint(index: index)
            }
            vertices.append(Vertex(
                position: placement.position,
                handles: placement.handles,
                color: color.literalValue.map(PenMeshColor.init(penMesh:)) ?? .black
            ))
        }
        try self.init(columns: columns, rows: rows, vertices: vertices)
    }
}
