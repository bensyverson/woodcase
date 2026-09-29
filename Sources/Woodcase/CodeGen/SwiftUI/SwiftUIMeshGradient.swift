//
//  SwiftUIMeshGradient.swift
//  Woodcase
//

import Foundation

/// A .pen mesh gradient fill as SwiftUI: always its native `MeshGradient` (Ben's ruling,
/// 2026-09-26), never a baked raster.
///
/// The grid is the renderer's own (``PenMeshGrid``), so Pen's rules for when a mesh is
/// drawn at all, where a malformed point sits and which handle a point omits are decided
/// once. Each vertex is then written as Pen would save it
/// (``PenMeshPoint/canonicalized(defaults:)``) — bare when its handles are the grid's
/// defaults, otherwise with the handles that differ, still relative — into the support
/// file's `PenMeshGradient(columns:rows:points:colors:)`, a `ShapeStyle` that resolves to
/// a `MeshGradient`.
///
/// Handed Pen's grid directly, `MeshGradient` interpolates its own way — not Pen's bicubic
/// patches and smoothstep-eased, unpremultiplied colors — and measured MAE 0.4–3.2 on
/// smooth meshes, 5.0 on a translucent one and 7.1 on a folded one. So the style splits
/// each Pen cell into 8 × 8 cells whose corners, tangents and colors it takes from Pen's
/// patch, which brings every `render-mesh-gradients` board, the fold included, to within
/// 0.9 of Pen's export. A fold still overdraws in SwiftUI's order rather than Pen's;
/// lint's `mesh-gradient-distorted` warns about it.
enum SwiftUIMeshGradient {
    /// The mesh's paint, or `nil` when it paints nothing: Pen would not draw it (a missing
    /// field, a count that does not match the grid, a single row or column), or a color
    /// names a variable `color` cannot write (reported in `unemitted`).
    ///
    /// A color variable is read through the theme (`theme.brand`), so `PenMeshGradient`
    /// resolves it in the view's environment; a color string is written as Pen's mesh
    /// reads it (``PenMeshColor/hexColor(penMesh:)``), a malformed one included.
    static func content(
        _ fill: PenFill.PenMeshGradientFill, color: SwiftUIGradient.ColorCode, unemitted: inout [String]
    ) -> SwiftUIPaintLayer.Content? {
        guard let grid = try? PenMeshGrid(fill), grid.patchColumns > 0, grid.patchRows > 0 else { return nil }
        var colorCode: [String] = []
        for value in fill.colors ?? [] {
            switch value {
            case let .literal(text):
                colorCode.append(SwiftUILiteral.color(PenMeshColor.hexColor(penMesh: text)))
            case .variable:
                guard let code = color(value, &unemitted)?.code else { return nil }
                colorCode.append(code)
            }
        }
        let defaults = PenMeshPoint.Handles.defaults(columns: grid.columns, rows: grid.rows)
        let points = grid.vertices.map { vertex(point(for: $0).canonicalized(defaults: defaults)) }
        let arguments = [
            "columns: \(grid.columns)",
            "rows: \(grid.rows)",
            "points: [\(points.joined(separator: ", "))]",
            "colors: [\(colorCode.joined(separator: ", "))]",
        ]
        return .style("PenMeshGradient(\(arguments.joined(separator: ", ")))")
    }

    /// A placed vertex as a point object with all four handles, for canonicalizing.
    private static func point(for vertex: PenMeshGrid.Vertex) -> PenMeshPoint {
        .object(PenMeshPoint.Object(
            position: vertex.position,
            leftHandle: vertex.handles.left,
            rightHandle: vertex.handles.right,
            topHandle: vertex.handles.top,
            bottomHandle: vertex.handles.bottom
        ))
    }

    /// A canonical point as the support file's `PenMeshVertex`: `[x, y]` when bare,
    /// `PenMeshVertex([x, y], left: […], …)` with only the handles it keeps otherwise.
    private static func vertex(_ point: PenMeshPoint) -> String {
        switch point {
        case let .bare(position):
            return vector(position)
        case let .object(object):
            let handles: [(String, PenMeshPoint.Vector?)] = [
                ("left", object.leftHandle), ("right", object.rightHandle),
                ("top", object.topHandle), ("bottom", object.bottomHandle),
            ]
            let arguments = [vector(object.position)] + handles.compactMap { label, handle in
                handle.map { "\(label): \(vector($0))" }
            }
            return "PenMeshVertex(\(arguments.joined(separator: ", ")))"
        case .malformed:
            // Only a point read from a file can be malformed; a placed vertex never is.
            return "[0, 0]"
        }
    }

    /// `[x, y]`.
    private static func vector(_ vector: PenMeshPoint.Vector) -> String {
        "[\(SwiftUILiteral.number(vector.x)), \(SwiftUILiteral.number(vector.y))]"
    }
}
