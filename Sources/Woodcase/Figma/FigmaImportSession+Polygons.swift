//
//  FigmaImportSession+Polygons.swift
//  Woodcase
//

import Foundation

extension FigmaImportSession {
    /// A line as a Pen line: its length is its `size`, its turn its transform's, and Pen
    /// draws it from the box's top-left corner to its bottom-right, as Figma does along +x.
    mutating func line(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        return .line(PenNode.LineData(
            width: .fixed(size.width), height: .fixed(size.height), stroke: graphics.stroke,
            strokeWidth: graphics.strokeWidth, strokeLinecap: graphics.strokeLinecap,
            strokeLinejoin: graphics.strokeLinejoin, strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// A regular polygon as a Pen polygon whose corners land on Figma's.
    ///
    /// Both put the first corner at the top and go clockwise, on an ellipse. Pen inscribes
    /// that ellipse in its box, so an odd or six-sided polygon leaves a gap below or beside
    /// it; Figma stretches the polygon's own bounds over the box. So the Pen box is grown,
    /// and its anchor moved, until the polygon's bounds are Figma's box. A polygon whose
    /// sides are a multiple of four fills the box in both and keeps it. A gradient or image
    /// is laid over Pen's larger box, which is reported.
    mutating func polygon(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        let size = size(of: record)
        let sides = max(3, Int(record["count"]?.uintValue ?? 3))
        let graphics = graphics(of: record, common: &common)
        let unit = Self.unitPolygon(sides: sides)
        let fit = Self.fit(unit, width: size.width, height: size.height)
        if abs(fit.width - size.width) > 1e-9 || abs(fit.height - size.height) > 1e-9 {
            let anchor = (FigmaTransform(record["transform"]) ?? .identity).apply(x: fit.x, y: fit.y)
            common.x = .literal(anchor.x)
            common.y = .literal(anchor.y)
            let paints = [graphics.fills, graphics.stroke].compactMap { $0?.all }.joined()
            if paints.contains(where: { if case .color = $0 { false } else { true } }) {
                report(.polygonBox, .approximated, on: record)
            }
        }
        return .polygon(PenNode.PolygonData(
            width: .fixed(fit.width), height: .fixed(fit.height), polygonCount: .literal(Double(sides)),
            cornerRadius: cornerRadius(of: record),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// A star as a Pen path: from its own geometry blob when the clipboard carries one,
    /// else computed — `count` outer points on the unit circle, first at the top, and as
    /// many inner points between them at `starInnerScale` of the radius, the whole star
    /// stretched so its bounds are the box. Pen has no rounded star; a corner radius is
    /// reported.
    mutating func star(_ record: KiwiRecord, common: inout PenNodeCommon) throws(FigmaImportError) -> PenNode.Kind {
        if record["vectorData"]?["vectorNetworkBlob"] != nil {
            return try vector(record, common: &common)
        }
        let size = size(of: record)
        let points = max(3, Int(record["count"]?.uintValue ?? 5))
        let ratio = record["starInnerScale"]?.doubleValue ?? 0.382
        let graphics = graphics(of: record, common: &common)
        if (record["cornerRadius"]?.doubleValue ?? 0) > 0 {
            report(.shapeCornerRadius, .approximated, on: record)
        }
        var unit: [(x: Double, y: Double)] = []
        for index in 0 ..< 2 * points {
            let angle = Double(index) * .pi / Double(points)
            let radius = index.isMultiple(of: 2) ? 1 : ratio
            unit.append((radius * sin(angle), -radius * cos(angle)))
        }
        let bounds = Self.bounds(of: unit)
        let corners = unit.map { point in
            FigmaPoint(
                x: bounds.width > 0 ? (point.x - bounds.minX) / bounds.width * size.width : 0,
                y: bounds.height > 0 ? (point.y - bounds.minY) / bounds.height * size.height : 0
            )
        }
        let commands = [FigmaPathCommand.move(to: corners[0])] + corners.dropFirst().map { .line(to: $0) } + [.close]
        return .path(PenNode.PathData(
            width: .fixed(size.width), height: .fixed(size.height), geometry: Self.svgPathData(commands),
            viewBox: PenViewBox(x: 0, y: 0, width: size.width, height: size.height),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// A regular polygon's corners on the unit circle, the first at the top, clockwise on
    /// screen — Pen's order (`PenShapeGeometry.polygonVertices(in:sides:)`).
    static func unitPolygon(sides: Int) -> [(x: Double, y: Double)] {
        (0 ..< sides).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sides)
            return (sin(angle), -cos(angle))
        }
    }

    /// The Pen box, in the node's coordinates, whose inscribed unit-circle polygon `unit`
    /// has its bounds at `(0, 0, width, height)`.
    static func fit(_ unit: [(x: Double, y: Double)], width: Double, height: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        let bounds = bounds(of: unit)
        let boxWidth = bounds.width > 0 ? 2 * width / bounds.width : width
        let boxHeight = bounds.height > 0 ? 2 * height / bounds.height : height
        return (-boxWidth / 2 * (1 + bounds.minX), -boxHeight / 2 * (1 + bounds.minY), boxWidth, boxHeight)
    }

    /// The bounds of `points`.
    private static func bounds(of points: [(x: Double, y: Double)]) -> (minX: Double, minY: Double, width: Double, height: Double) {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return (minX, minY, (xs.max() ?? 0) - minX, (ys.max() ?? 0) - minY)
    }
}
