//
//  ReactEmitter+GradientOutset.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// How much larger than the node's box a gradient's tile is drawn, so it reaches an
    /// element that grows `outsets` past the box: 1 with no outsets; else enough to cover
    /// the farthest side when the box and the outsets are known numbers, and three boxes
    /// (a box's reach on every side) when they are not.
    static func tileGrowth(box: FillBox, outsets: EdgeLengths) -> Double {
        guard !outsets.isZero else { return 1 }
        guard let width = box.width, let height = box.height, width > 0, height > 0,
              let top = outsets.top.literalPoints, let right = outsets.right.literalPoints,
              let bottom = outsets.bottom.literalPoints, let left = outsets.left.literalPoints
        else { return 3 }
        return 1 + 2 * max(left / width, right / width, top / height, bottom / height, 0)
    }

    /// A tile `width` and `height` times the node's box, as a `background-size` on an
    /// element that grows `outsets` past that box.
    static func tileSize(width: Double, height: Double, outsets: EdgeLengths) -> String {
        let horizontal = outsets.left + outsets.right
        let vertical = outsets.top + outsets.bottom
        let across = horizontal.isZero ? cssPercent(width) : fraction(of: horizontal, width)
        let down = vertical.isZero ? cssPercent(height) : fraction(of: vertical, height)
        return "\(across) \(down)"
    }

    /// The `background-position` that centers a tile on the node's box within an element
    /// that grows `outsets` past it. A percentage position aligns that fraction of the
    /// tile with that fraction of the element, so 50% centers the tile on the element, and
    /// half the difference of the two sides' outsets moves it onto the node's box.
    static func tilePosition(outsets: EdgeLengths) -> String {
        let across = (outsets.left - outsets.right).scaled(by: 0.5)
        let down = (outsets.top - outsets.bottom).scaled(by: 0.5)
        guard !across.isZero || !down.isZero else { return CSSGradient.centered }
        let axis = { (shift: SymbolicLength) in shift.isZero ? "50%" : "calc(50% + \(shift.sumTerms))" }
        return "\(axis(across)) \(axis(down))"
    }

    /// How far a linear gradient's line grows at its start and its end when the box grows
    /// by `outsets`: the growth of the sides the line leaves from and arrives at, each
    /// projected onto the line's direction.
    static func lineGrowth(angle: Int, outsets: EdgeLengths) -> (start: SymbolicLength, end: SymbolicLength) {
        let radians = Double(angle) * .pi / 180
        // The CSS gradient line points along (sin θ, −cos θ) in y-down coordinates.
        let dx = cleaned(sin(radians))
        let dy = cleaned(-cos(radians))
        let start = (dx > 0 ? outsets.left : outsets.right).scaled(by: abs(dx))
            + (dy > 0 ? outsets.top : outsets.bottom).scaled(by: abs(dy))
        let end = (dx > 0 ? outsets.right : outsets.left).scaled(by: abs(dx))
            + (dy > 0 ? outsets.bottom : outsets.top).scaled(by: abs(dy))
        return (start, end)
    }

    /// A stop on the grown line, so it lands `fraction` of the way along the node box's
    /// own line: `start + fraction × (100% − start − end)`.
    static func stopPosition(_ fraction: Double, start: SymbolicLength, end: SymbolicLength) -> String {
        if fraction == 0 {
            return start.isZero ? "0%" : start.css
        }
        if fraction == 1 {
            return end.isZero ? "100%" : "calc(100% - \(end.operand))"
        }
        let span = "(100% - \((start + end).operand)) * \(cssNumber(fraction))"
        return start.isZero ? "calc(\(span))" : "calc(\(start.sumTerms) + \(span))"
    }

    /// `(100% − total) × factor`: a fraction of the node box's side on an element grown by `total`.
    static func fraction(of total: SymbolicLength, _ factor: Double) -> String {
        "calc((100% - \(total.operand)) * \(cssNumber(factor)))"
    }

    /// The point `fraction` of the way across the node box along one axis, on an element
    /// grown by `leading` before the box and `total` in all.
    static func boxPoint(_ leading: SymbolicLength, total: SymbolicLength, _ fraction: Double) -> String {
        let offset = "(100% - \(total.operand)) * \(cssNumber(fraction))"
        return leading.isZero ? "calc(\(offset))" : "calc(\(leading.sumTerms) + \(offset))"
    }

    /// Where a gradient's center lies on an element grown `outsets` past the node's box, as
    /// the `at …` of a radial or conic gradient: empty when it is the element's own center.
    static func gradientCenter(_ center: NormalizedPoint, outsets: EdgeLengths) -> String {
        if outsets.isZero {
            return center == .center ? "" : " at \(cssPercent(center.x)) \(cssPercent(center.y))"
        }
        let centered = outsets.left == outsets.right && outsets.top == outsets.bottom
        if centered, center == .center { return "" }
        let horizontal = outsets.left + outsets.right
        let vertical = outsets.top + outsets.bottom
        return " at \(boxPoint(outsets.left, total: horizontal, center.x)) \(boxPoint(outsets.top, total: vertical, center.y))"
    }

    /// `value` with floating-point dust around zero removed.
    private static func cleaned(_ value: Double) -> Double {
        abs(value) < 1e-9 ? 0 : value
    }
}
