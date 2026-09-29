//
//  StrokeRing.swift
//  Woodcase
//

/// Where a box's stroke sits relative to the node's box: how wide it is on each side,
/// and how far past the box each side's outer edge reaches.
///
/// Pen honors `strokeAlignment` for uniform and per-side widths alike, and the default
/// is center (`project/2026-09-26-text-and-stroke-fills.md`, finding 5): an inner
/// stroke reaches nothing past the box, a centered one half its width, an outer one all
/// of it.
struct StrokeRing: Friendly {
    /// The stroke's width on each side; a per-side stroke with a side left out is zero there.
    var widths: EdgeLengths

    /// How far the stroke's outer edge lies outside the node's box, per side.
    var outsets: EdgeLengths

    /// Creates the ring for a node's stroke width and alignment. An absent width is
    /// Pen's default of 1.
    init(_ stroke: any PenStrokable) {
        switch stroke.strokeWidth {
        case let .uniform(value):
            widths = EdgeLengths(all: SymbolicLength(value))
        case let .perSide(sides):
            let side = { (value: PenValue<Double>?) in value.map(SymbolicLength.init) ?? .zero }
            widths = EdgeLengths(
                top: side(sides.top), right: side(sides.right),
                bottom: side(sides.bottom), left: side(sides.left)
            )
        case nil:
            widths = EdgeLengths(all: SymbolicLength(points: 1))
        }
        let reach: Double = switch stroke.strokeAlignment ?? .center {
        case .inner: 0
        case .center: 0.5
        case .outer: 1
        }
        outsets = widths.map { $0.scaled(by: reach) }
    }

    /// The stroke's width inside the node's box, per side: its inner edge's inset.
    var insideWidths: EdgeLengths {
        widths - outsets
    }
}
