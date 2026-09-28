//
//  DocumentLinter+PerSideShape.swift
//  Woodcase
//

import Foundation

/// The `per-side-stroke-on-shape` check.
///
/// Pen strokes an ellipse, a polygon, a path or a line with a per-side `strokeWidth` as
/// one uniform stroke of the **top** width, the other three sides ignored, and with no
/// top draws no stroke (`render-per-side-shapes.pen`; finding F6 of
/// `project/2026-09-27-fidelity-gaps.md`). Every Woodcase target draws the same
/// (``PenStrokable/drawn(on:)``), so the file renders consistently — only not with the
/// widths it writes. A width whose sides all equal the top, or that writes only the top,
/// loses nothing and is clean, as is one with no stroke paint.
extension DocumentLinter {
    /// A finding when a sideless shape's per-side stroke width would draw differently
    /// from what it writes.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: At most one finding.
    static func perSideStrokeOnShape(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        let shape: (kind: String, stroke: any PenStrokable)? = switch node.kind {
        case let .ellipse(data): ("an ellipse", data)
        case let .polygon(data): ("a polygon", data)
        case let .path(data): ("a path", data)
        case let .line(data): ("a line", data)
        default: nil
        }
        guard let (kind, stroke) = shape, stroke.stroke != nil, case let .perSide(sides) = stroke.strokeWidth else { return [] }
        let others = [sides.right, sides.bottom, sides.left].compactMap(\.self)
        guard let top = sides.top else {
            return [finding(
                .perSideStrokeOnShape, row,
                "has a per-side strokeWidth with no top, but Pen strokes \(kind) at its top width alone, "
                    + "so it draws no stroke; Woodcase draws none either. Write one strokeWidth."
            )]
        }
        guard others.contains(where: { $0 != top }) else { return [] }
        return [finding(
            .perSideStrokeOnShape, row,
            "has a per-side strokeWidth (\(describe(sides))), but Pen strokes \(kind) at its top width "
                + "alone, all round (\(describe(top))); Woodcase draws it the same. Write one strokeWidth."
        )]
    }

    /// `top 12, right 2, bottom 6, left 0`, naming only the sides the width writes.
    private static func describe(_ sides: PenStrokeWidth.Sides) -> String {
        [("top", sides.top), ("right", sides.right), ("bottom", sides.bottom), ("left", sides.left)]
            .compactMap { name, value in value.map { "\(name) \(describe($0))" } }
            .joined(separator: ", ")
    }

    /// A width as written: a number, or `$name`.
    private static func describe(_ value: PenValue<Double>) -> String {
        switch value {
        case let .literal(number): number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case let .variable(name): "$\(name)"
        }
    }
}
