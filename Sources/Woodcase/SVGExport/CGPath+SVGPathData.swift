//
//  CGPath+SVGPathData.swift
//  Woodcase
//

import CoreGraphics

extension CGPath {
    /// The path as SVG path data (`d`): one absolute command per element — `M`, `L`, `Q`,
    /// `C`, `Z` — numbers as ``Swift/Double/svgNumber``.
    ///
    /// Every outline the SVG writer draws is the `CGPath` the CG renderer fills
    /// (``PenShapeBuilder``), so the two agree on the shape to the curve: an arc, a smoothed
    /// polygon corner or a per-corner radius is never re-derived from SVG's own primitives.
    var svgPathData: String {
        var out = ""
        func point(_ point: CGPoint) -> String {
            Double(point.x).svgNumber + " " + Double(point.y).svgNumber
        }
        applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                out += "M" + point(points[0])
            case .addLineToPoint:
                out += "L" + point(points[0])
            case .addQuadCurveToPoint:
                out += "Q" + point(points[0]) + " " + point(points[1])
            case .addCurveToPoint:
                out += "C" + point(points[0]) + " " + point(points[1]) + " " + point(points[2])
            case .closeSubpath:
                out += "Z"
            @unknown default:
                break
            }
        }
        return out
    }
}
