//
//  DocumentLinter+MeshPoint.swift
//  Woodcase
//

import Foundation

/// The malformed-point half of `mesh-gradient-dropped` and `mesh-gradient-distorted`.
///
/// A mesh point written in neither `[x, y]` nor object form is kept verbatim
/// (``PenMeshPoint/malformed(_:)``), and Pen reads it its own way
/// (``PenMeshPoint/placement(gridPosition:defaults:)``):
///
/// - One Pen cannot place — `[1]`, `["0.3", "0.2"]`, a `position` or handle that is not an
///   array — leaves the whole fill unpainted, so it is **dropped**.
/// - One Pen places anyway — `"oops"` at its grid position, `[0.3, 0.2, 9]` at its first
///   two numbers — is painted, but from Pen's repair rather than from what the file says,
///   and Pen rewrites it on save. That is a mesh Pen paints but not as authored, the
///   definition of **distorted**, so it is a warning there rather than a check of its own:
///   its fix, like a `#RGBA` color's, is to write the value Pen already draws, which the
///   finding names.
extension DocumentLinter {
    /// Why Pen paints nothing for a mesh whose grid is well formed: the points it cannot
    /// place. `nil` when there are none or the grid itself is not drawable.
    static func unplaceablePointsReason(_ fill: PenFill.PenMeshGradientFill) -> String? {
        let named = malformedPoints(fill).filter { $0.placement == nil }.map { "vertex \($0.index + 1) `\($0.written)`" }
        guard !named.isEmpty else { return nil }
        return "with \(named.joined(separator: ", ")), which Pen cannot read as a position or handle; "
            + "Pen keeps the fill and paints nothing. Write each point as `[x, y]` or "
            + "`{\"position\": [x, y], …}` with two-number handles."
    }

    /// The malformed points Pen places anyway, as a distortion, or `nil` if there are none.
    static func repairedPointsProblem(_ fill: PenFill.PenMeshGradientFill) -> String? {
        guard let defaults = fill.defaultHandles else { return nil }
        let named = malformedPoints(fill).compactMap { point -> String? in
            guard let placement = point.placement else { return nil }
            let object = PenMeshPoint.Object(
                position: placement.position,
                leftHandle: placement.handles.left, rightHandle: placement.handles.right,
                topHandle: placement.handles.top, bottomHandle: placement.handles.bottom
            )
            let drawn = PenMeshPoint.object(object).canonicalized(defaults: defaults)
            return "vertex \(point.index + 1) `\(point.written)` as `\(compactJSON(drawn))`"
        }
        guard !named.isEmpty else { return nil }
        return "points in neither `[x, y]` nor object form, which Pen draws its own way and "
            + "rewrites on save: \(named.joined(separator: ", ")); write what Pen draws"
    }

    // MARK: - Private

    /// One malformed point of a drawable grid: where it is, what the file wrote, and
    /// where Pen draws it (`nil` if Pen cannot).
    private struct MalformedPoint {
        let index: Int
        let written: String
        let placement: PenMeshPoint.Placement?
    }

    /// Every malformed point of a mesh whose counts fit a grid of at least 2×2.
    private static func malformedPoints(_ fill: PenFill.PenMeshGradientFill) -> [MalformedPoint] {
        guard let columns = fill.columns, let rows = fill.rows, columns >= 2, rows >= 2,
              let points = fill.points, points.count == columns * rows,
              let defaults = fill.defaultHandles
        else { return [] }
        return points.enumerated().compactMap { index, point in
            guard case let .malformed(raw) = point else { return nil }
            let gridPosition = PenMeshPoint.gridPosition(
                column: index % columns, row: index / columns, columns: columns, rows: rows
            )
            return MalformedPoint(
                index: index,
                written: compactJSON(raw),
                placement: point.placement(gridPosition: gridPosition, defaults: defaults)
            )
        }
    }

    /// A value as one line of JSON with sorted keys, for quoting in a message.
    private static func compactJSON(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "?" }
        return String(decoding: data, as: UTF8.self)
    }
}
