//
//  PenNode+ConnectionDrawingOutline.swift
//  Woodcase
//

import CoreGraphics

public extension PenNode.ConnectionData.Drawing {
    /// Whether `point` is on what the connection paints: the stroke band along its line,
    /// a chevron's stroked arms, or a filled arrowhead.
    ///
    /// The band is the true stroked outline of the polyline, with its caps and joins, as a
    /// line's is (``PenLayoutEngine/strokeBandContains(_:of:box:)``) — so a click inside the
    /// route's bounding box but off the route misses.
    ///
    /// - Parameters:
    ///   - point: A point on the canvas.
    ///   - tolerance: How far outside the painted shape still counts, in points: an editor
    ///     passes a few so a hairline can be clicked. Defaults to none.
    /// - Returns: `true` when the point is on the painted shape, or within `tolerance` of it.
    func contains(_ point: PenPoint, tolerance: Double = 0) -> Bool {
        let point = point.cgPoint
        let grow = CGFloat(max(tolerance, 0) * 2)
        if bandOutline(linePath, extra: grow).contains(point) { return true }
        if let arms = strokedArrowheadPath, bandOutline(arms, extra: grow).contains(point) { return true }
        guard let heads = filledArrowheadPath else { return false }
        if heads.contains(point) { return true }
        return grow > 0 && heads.copy(strokingWithWidth: grow, lineCap: .round, lineJoin: .round, miterLimit: 1)
            .contains(point)
    }

    /// Everything the connection paints, on the canvas: the stroke band along its line, a
    /// chevron's band and every filled arrowhead.
    ///
    /// This is a connection's extent for an export, a culling pass or an invalidated region:
    /// its layout rect says nothing about where it draws.
    ///
    /// A connection that paints nothing — a zero-width stroke — answers an empty rect at
    /// its source's anchor.
    var paintedExtent: PenRect {
        var parts = [bandOutline(linePath, extra: 0).boundingBoxOfPath]
        if let arms = strokedArrowheadPath {
            parts.append(bandOutline(arms, extra: 0).boundingBoxOfPath)
        }
        if let heads = filledArrowheadPath {
            parts.append(heads.boundingBoxOfPath)
        }
        let painted = parts.filter { !$0.isNull && !$0.isEmpty }
        guard let first = painted.first else {
            let anchor = route.points.first ?? .zero
            return PenRect(x: anchor.x, y: anchor.y, width: 0, height: 0)
        }
        let extent = painted.dropFirst().reduce(first) { $0.union($1) }
        return PenRect(x: Double(extent.minX), y: Double(extent.minY), width: Double(extent.width),
                       height: Double(extent.height))
    }

    // MARK: - CoreGraphics paths

    /// The polyline the stroke paints.
    internal var linePath: CGPath {
        Self.polyline(line)
    }

    /// The chevrons' arms, to stroke as the line is; `nil` when no arrowhead is a chevron.
    internal var strokedArrowheadPath: CGPath? {
        let path = CGMutablePath()
        for case let .stroked(points) in arrowheads {
            path.addPath(Self.polyline(points))
        }
        return path.isEmpty ? nil : path
    }

    /// The triangles and discs, to fill with the stroke's paint; `nil` when there are none.
    internal var filledArrowheadPath: CGPath? {
        let path = CGMutablePath()
        for head in arrowheads {
            switch head {
            case let .filled(points):
                path.addPath(Self.polyline(points))
                path.closeSubpath()
            case let .disc(center, radius):
                path.addEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
                ))
            case .stroked:
                continue
            }
        }
        return path.isEmpty ? nil : path
    }

    /// The CoreGraphics cap the stroke's cap names.
    internal var cap: CGLineCap {
        switch strokeLinecap {
        case .butt, nil: .butt
        case .round: .round
        case .square: .square
        }
    }

    /// The CoreGraphics join the stroke's join names.
    internal var join: CGLineJoin {
        switch strokeLinejoin {
        case .miter, nil: .miter
        case .bevel: .bevel
        case .round: .round
        }
    }

    /// `path` stroked at the stroke's width, grown by `extra`, with its caps and joins.
    private func bandOutline(_ path: CGPath, extra: CGFloat) -> CGPath {
        path.copy(
            strokingWithWidth: CGFloat(strokeWidth) + extra, lineCap: cap, lineJoin: join,
            miterLimit: CGFloat(PenNode.defaultMiterLimit)
        )
    }

    /// An open path through `points`.
    private static func polyline(_ points: [PenPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first.cgPoint)
        for point in points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }
        return path
    }
}
