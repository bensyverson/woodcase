//
//  PenStrokable+Drawn.swift
//  Woodcase
//

public extension PenStrokable {
    /// This stroke as Pen draws it on `node`.
    ///
    /// Pen lays a per-side `strokeWidth` along the sides of a box — a frame, a rectangle, a
    /// browser node — and keeps it per side there. Any other shape — an ellipse, a polygon,
    /// a path, a line — Pen strokes with one uniform stroke of the **top** width, the other
    /// three sides ignored, and with no top it draws no stroke; alignment, join and cap
    /// apply as they do to any uniform stroke (`render-per-side-shapes.pen`, Pen 1.2.14).
    /// Pen's choice of the top side looks arbitrary, so the fixture pins it. With no
    /// `strokeWidth` at all, Pen draws no stroke on any kind of node, so the stroke comes
    /// back with no paint (`render-stroke-no-width.pen`). Every target draws the stroke
    /// this returns; a uniform width is returned unchanged.
    ///
    /// - Parameter node: The node the stroke is drawn on, which says whether it has sides.
    /// - Returns: The stroke with a per-side width on a sideless shape made uniform, and
    ///   with no paint when it has no width.
    func drawn(on node: PenNode) -> Self {
        guard strokeWidth != nil else {
            var drawn = self
            drawn.stroke = nil
            return drawn
        }
        guard case let .perSide(sides) = strokeWidth else { return self }
        switch node.kind {
        case .frame, .rectangle, .browser:
            return self
        default:
            var drawn = self
            drawn.strokeWidth = .uniform(sides.top ?? .literal(0))
            return drawn
        }
    }
}
