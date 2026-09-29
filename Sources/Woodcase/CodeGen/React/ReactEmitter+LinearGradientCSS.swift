//
//  ReactEmitter+LinearGradientCSS.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// A slope below this is flat: the ramp runs along one of the box's axes.
    private static let flatSlope = 1e-9

    /// A linear gradient at Pen's geometry.
    ///
    /// Pen lays the ramp out in the normalized box, so its isolines are fixed there and
    /// slant with the box's proportions; a CSS angle is fixed on screen instead, and its
    /// line runs corner to corner. Two forms state Pen's ramp exactly on a box of any size:
    ///
    /// - a ramp along one axis keeps its angle, and its stops move to where Pen's center
    ///   and size put them on that axis;
    /// - an off-axis ramp uses a corner keyword (`to top left`), whose isolines CSS lays
    ///   parallel to the tile's other diagonal — an affine rule, so a tile of the right
    ///   proportions *in the box's own percentages* carries Pen's slant at any size. The
    ///   tile is centered on the box and at least covers it; the stops are placed along its
    ///   line where Pen's ramp puts them.
    static func cssLinearGradient(
        _ geometry: GradientGeometry,
        stops: GradientStops,
        box: FillBox,
        outsets: EdgeLengths
    ) -> CSSGradient? {
        guard let ramp = geometry.linearRamp else { return nil }
        let center = ramp.position(at: .center)
        if abs(ramp.du) < flatSlope || abs(ramp.dv) < flatSlope {
            return axisLinearGradient(ramp, rotation: geometry.rotation, center: center, stops: stops, outsets: outsets)
        }

        let slope = max(abs(ramp.du), abs(ramp.dv))
        let growth = tileGrowth(box: box, outsets: outsets)
        let keyword = "to \(ramp.dv > 0 ? "bottom" : "top") \(ramp.du > 0 ? "right" : "left")"
        // A corner ramp crosses its tile from one corner's isoline to the opposite's, which
        // on this tile is twice the steeper slope, grown with the tile.
        let span = 2 * slope * growth
        let list = stops.map { "\($0.color) \(cssPercent(0.5 + ($0.position - center) / span))" }
        return CSSGradient(
            image: "linear-gradient(\(keyword), \(list.joined(separator: ", ")))",
            size: tileSize(
                width: slope / abs(ramp.du) * growth,
                height: slope / abs(ramp.dv) * growth,
                outsets: outsets
            ),
            position: tilePosition(outsets: outsets)
        )
    }

    /// A ramp along one of the box's axes: its CSS angle, with the stops where Pen's ramp
    /// puts them along the node box's side, pulled onto the node box when the element
    /// reaches past it.
    private static func axisLinearGradient(
        _ ramp: GradientGeometry.LinearRamp,
        rotation: Double,
        center: Double,
        stops: GradientStops,
        outsets: EdgeLengths
    ) -> CSSGradient {
        let vertical = abs(ramp.du) < flatSlope
        let slope = vertical ? ramp.dv : ramp.du
        let angle = cssAxisAngle(vertical ? (slope > 0 ? 180 : 0) : (slope > 0 ? 90 : 270), rotation: rotation)
        // The fraction of the node box's side, from the line's start, at each stop.
        let fractions = stops.map { 0.5 + ($0.position - center) / abs(slope) }
        let list: [String]
        if outsets.isZero {
            list = zip(stops, fractions).map { "\($0.color) \(cssPercent($1))" }
        } else {
            let (start, end) = lineGrowth(angle: angle, outsets: outsets)
            list = zip(stops, fractions).map { "\($0.color) \(stopPosition($1, start: start, end: end))" }
        }
        return CSSGradient(image: "linear-gradient(\(angle)deg, \(list.joined(separator: ", ")))")
    }

    /// The CSS angle of an axis ramp: Pen's rotation negated (Pen turns counter-clockwise,
    /// CSS clockwise) when it names the same direction, as a quarter turn does, else the
    /// direction itself.
    private static func cssAxisAngle(_ direction: Int, rotation: Double) -> Int {
        let negated = -rotation
        guard negated == negated.rounded(), abs(negated) < 1e6 else { return direction }
        let degrees = Int(negated)
        return ((degrees - direction) % 360 + 360) % 360 == 0 ? degrees : direction
    }
}
