//
//  DocumentLinter+MeshGradient.swift
//  Woodcase
//

import Foundation

/// The `mesh-gradient-dropped` and `mesh-gradient-distorted` checks.
///
/// Both read every `mesh_gradient` paint a node carries, in its fills and in its
/// stroke, and both describe what **Pen** does with it, observed with the headless
/// `pen` CLI (`project/2026-09-26-what-pen-drops-from-a-file.md`):
///
/// - `points` or `colors` that do not number `columns × rows`, or a mesh missing one
///   of the four: Pen removes the whole fill when it opens the file.
/// - fewer than two columns or two rows: Pen keeps the fill and paints nothing, since
///   no patch spans a single row or column.
/// - a colour of any length but 3, 6 or 8 digits after one leading `#` — 4-digit `#RGBA`,
///   a 5-digit typo, an empty string: Pen keeps it and its mesh paints it as nothing.
/// - a colour of a readable length with a digit that is not hex (`red`, `#eGeGeG`): Pen
///   paints another colour, the one ``PenMeshColor/hexColor(penMesh:)`` reads.
/// - a patch whose handles fold it over itself: Pen paints it, overlapping itself and
///   leaving part of the box bare. See ``MeshFoldDetector`` for the test.
/// - a point written in neither `[x, y]` nor object form
///   (``PenMeshPoint/malformed(_:)``): one Pen cannot place leaves the whole fill
///   unpainted; one it places anyway is painted where Pen puts it, not where the file
///   says. See `DocumentLinter+MeshPoint.swift`.
///
/// Counts, a grid under 2×2 and an unplaceable point are ``LintCheck/meshGradientDropped``
/// errors; a colour Pen misreads, a fold and a point Pen places anyway are
/// ``LintCheck/meshGradientDistorted`` warnings. A disabled paint is skipped: nothing
/// is painted either way. The Woodcase ruling behind all of them is that Woodcase never
/// writes a file Pen renders badly, whatever Woodcase's own renderer makes of it.
extension DocumentLinter {
    /// Every mesh finding for one node, fills first, then the stroke.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)` — so a `$colour`
    ///     is judged on the value it resolves to.
    /// - Returns: At most one dropped finding per paint; when a paint is not dropped, at
    ///   most one distorted finding for it.
    static func meshGradientFindings(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        meshPaints(of: node.kind).flatMap { paint -> [LintFinding] in
            let label = paint.total > 1 ? "\(paint.role) \(paint.ordinal) of \(paint.total)" : paint.role
            if let reason = droppedReason(paint.fill) {
                return [finding(
                    .meshGradientDropped, row,
                    "has a mesh gradient \(label) \(reason) Write `columns × rows` points and "
                        + "colours, at least 2×2."
                )]
            }
            if let unplaceable = unplaceablePointsReason(paint.fill) {
                return [finding(.meshGradientDropped, row, "has a mesh gradient \(label) \(unplaceable)")]
            }
            let problems = distortions(paint.fill)
            guard !problems.isEmpty else { return [] }
            return [finding(
                .meshGradientDistorted, row,
                "has a mesh gradient \(label) Pen paints wrong: \(problems.joined(separator: "; "))."
            )]
        }
    }

    // MARK: - Dropped

    /// Why Pen paints nothing for a mesh, or `nil` when the grid is well formed.
    private static func droppedReason(_ fill: PenFill.PenMeshGradientFill) -> String? {
        let missing = [
            fill.columns == nil ? "columns" : nil,
            fill.rows == nil ? "rows" : nil,
            fill.points == nil ? "points" : nil,
            fill.colors == nil ? "colors" : nil,
        ].compactMap(\.self)
        if !missing.isEmpty {
            return "with no `\(missing.joined(separator: "`, `"))`; Pen removes the whole fill "
                + "when it opens the file."
        }
        guard let columns = fill.columns, let rows = fill.rows,
              let points = fill.points, let colors = fill.colors
        else { return nil }

        let grid = "\(columns)×\(rows)"
        let vertices = columns * rows
        if points.count != vertices || colors.count != vertices {
            var counts: [String] = []
            if points.count != vertices { counts.append("\(points.count) points") }
            if colors.count != vertices { counts.append("\(colors.count) colours") }
            return "with \(counts.joined(separator: " and ")) for a \(grid) grid of \(vertices) vertices; "
                + "Pen removes the whole fill when it opens the file."
        }
        if columns < 2 || rows < 2 {
            return "on a \(grid) grid: no patch spans a single row or column, so Pen keeps the "
                + "fill and paints nothing."
        }
        return nil
    }

    // MARK: - Distorted

    /// What Pen paints wrong in a well-formed mesh: colours it reads as nothing or as
    /// another colour, points it places anyway, then folds.
    private static func distortions(_ fill: PenFill.PenMeshGradientFill) -> [String] {
        var problems: [String] = []

        let colors = (fill.colors ?? []).enumerated().compactMap { index, color in
            color.literalValue.map { (vertex: index + 1, text: $0) }
        }
        let unread = colors.filter { PenMeshColor.penMeshDigits($0.text) == nil }.map { color in
            let fix = isRGBAHex(color.text) ? " (write `\(expanded(color.text))`)" : ""
            return "vertex \(color.vertex) `\(color.text)`\(fix)"
        }
        if !unread.isEmpty {
            problems.append(
                "colours Pen's mesh reads as nothing (it reads 3, 6 or 8 hex digits), at "
                    + unread.joined(separator: ", ")
            )
        }
        let coerced = colors.compactMap { color -> String? in
            guard let digits = PenMeshColor.penMeshDigits(color.text),
                  !digits.allSatisfy({ $0 < 128 && Character(Unicode.Scalar(UInt8($0))).isHexDigit })
            else { return nil }
            return "vertex \(color.vertex) `\(color.text)` as `\(hexString(PenMeshColor.hexColor(penMesh: color.text), digits: digits.count))`"
        }
        if !coerced.isEmpty {
            problems.append("colours that are not hex, which Pen's mesh reads as another colour: " + coerced.joined(separator: ", "))
        }

        if let repaired = repairedPointsProblem(fill) {
            problems.append(repaired)
        }

        let folded = MeshFoldDetector.foldedPatches(in: fill)
        if !folded.isEmpty {
            let names = folded.map { "column \($0.column + 1), row \($0.row + 1)" }
            problems.append(
                "the patch at \(names.joined(separator: "; ")) folds over itself, overlapping "
                    + "its own paint and leaving part of the box bare; pull its handles back "
                    + "inside the patch"
            )
        }
        return problems
    }

    /// Whether a colour is 4-digit hex: `#` and exactly four hex digits.
    private static func isRGBAHex(_ color: String) -> Bool {
        color.count == 5 && color.hasPrefix("#") && color.dropFirst().allSatisfy(\.isHexDigit)
    }

    /// A colour as `#RRGGBB`, or `#RRGGBBAA` when it was read from eight digits.
    private static func hexString(_ color: PenHexColor, digits: Int) -> String {
        let channels = digits == 8 ? [color.red, color.green, color.blue, color.alpha] : [color.red, color.green, color.blue]
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }

    /// `#RGBA` spelled out as `#RRGGBBAA`.
    private static func expanded(_ rgba: String) -> String {
        "#" + rgba.dropFirst().map { "\($0)\($0)" }.joined().uppercased()
    }

    // MARK: - Paints

    /// One mesh paint on a node: whether it is a fill or the stroke, its 1-based place
    /// among that role's paints and how many paints the role has, and the mesh itself.
    private struct MeshPaint {
        let role: String
        let ordinal: Int
        let total: Int
        let fill: PenFill.PenMeshGradientFill
    }

    /// Every enabled mesh paint on a node, fills first.
    private static func meshPaints(of kind: PenNode.Kind) -> [MeshPaint] {
        let lists = kind.paintLists
        return meshes(in: lists.fills, role: "fill") + meshes(in: lists.stroke, role: "stroke")
    }

    /// The enabled meshes in one paint list, numbered by their place in it.
    private static func meshes(in fills: PenFills?, role: String) -> [MeshPaint] {
        let all = fills?.all ?? []
        return all.enumerated().compactMap { index, fill in
            guard case let .meshGradient(mesh) = fill, mesh.enabled?.literalValue != false else { return nil }
            return MeshPaint(role: role, ordinal: index + 1, total: all.count, fill: mesh)
        }
    }
}
