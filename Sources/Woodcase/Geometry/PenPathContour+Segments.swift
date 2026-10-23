import Foundation

extension PenPathContour {
    /// How many segments the contour draws: one between each pair of consecutive anchors,
    /// and on a closed contour of two or more anchors the closing one back to the first.
    var segmentCount: Int {
        guard anchors.count > 1 else { return 0 }
        return isClosed ? anchors.count : anchors.count - 1
    }

    /// One segment's four control points, as ``PenPath/init(contours:)`` draws it: a line
    /// when both facing handles are retracted, otherwise a cubic.
    struct Segment {
        /// The start anchor's point.
        var start: PenPoint
        /// The start anchor's out handle.
        var control1: PenPoint
        /// The end anchor's in handle.
        var control2: PenPoint
        /// The end anchor's point.
        var end: PenPoint
        /// Whether the segment is drawn as a straight line.
        var isLine: Bool

        /// The point at `t`.
        func point(at t: Double) -> PenPoint {
            if isLine {
                return Self.lerp(start, end, t)
            }
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return PenPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                y: a * start.y + b * control1.y + c * control2.y + d * end.y
            )
        }

        /// The first derivative at `t` of a cubic.
        func velocity(at t: Double) -> PenPoint {
            let u = 1 - t
            let a = 3 * u * u, b = 6 * u * t, c = 3 * t * t
            return PenPoint(
                x: a * (control1.x - start.x) + b * (control2.x - control1.x) + c * (end.x - control2.x),
                y: a * (control1.y - start.y) + b * (control2.y - control1.y) + c * (end.y - control2.y)
            )
        }

        /// The second derivative at `t` of a cubic.
        func acceleration(at t: Double) -> PenPoint {
            let u = 1 - t
            return PenPoint(
                x: 6 * u * (control2.x - 2 * control1.x + start.x) + 6 * t * (end.x - 2 * control2.x + control1.x),
                y: 6 * u * (control2.y - 2 * control1.y + start.y) + 6 * t * (end.y - 2 * control2.y + control1.y)
            )
        }

        /// The point a fraction `t` of the way from `a` to `b`.
        static func lerp(_ a: PenPoint, _ b: PenPoint, _ t: Double) -> PenPoint {
            PenPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// The segment at an index below ``segmentCount``.
    func segment(_ index: Int) -> Segment {
        let from = anchors[index]
        let to = anchors[(index + 1) % anchors.count]
        return Segment(
            start: from.point, control1: from.outHandle, control2: to.inHandle, end: to.point,
            isLine: !from.hasOutHandle && !to.hasInHandle
        )
    }
}
