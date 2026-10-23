import Foundation

public extension PenPathContour {
    /// Where on a contour a point is nearest: the segment, how far along it, and the point.
    struct NearestPoint: Friendly {
        /// The segment: segment `i` joins anchor `i` to anchor `i + 1`, and on a closed
        /// contour the last, `anchors.count - 1`, is the closing segment back to anchor 0.
        public var segment: Int
        /// How far along the segment, from 0 at its start anchor to 1 at its end anchor —
        /// the curve's own parameter, which ``PenPathContour/insertingAnchor(inSegment:at:)``
        /// takes.
        public var t: Double
        /// The point on the segment.
        public var point: PenPoint
        /// How far ``point`` is from the point asked about.
        public var distance: Double

        /// Creates a nearest point.
        ///
        /// - Parameters:
        ///   - segment: The segment index.
        ///   - t: The parameter along it.
        ///   - point: The point on it.
        ///   - distance: Its distance from the point asked about.
        public init(segment: Int, t: Double, point: PenPoint, distance: Double) {
            self.segment = segment
            self.t = t
            self.point = point
            self.distance = distance
        }
    }

    /// The point of the contour's drawn segments nearest a point — where "add an anchor on
    /// a segment" lands.
    ///
    /// A straight segment answers exactly, by projection. A cubic is sampled, and each
    /// sample nearer than its neighbors is refined by Newton's method on the squared
    /// distance, so the answer is good to about 10⁻⁶ of a point. On a tie the earlier
    /// segment wins.
    ///
    /// - Parameter target: The point, in the contour's space.
    /// - Returns: The nearest point, or `nil` for a contour with no segment.
    func nearestPoint(to target: PenPoint) -> NearestPoint? {
        var best: NearestPoint?
        for index in 0 ..< segmentCount {
            let piece = segment(index)
            let t = piece.isLine ? Self.projection(of: target, on: piece) : Self.nearestParameter(to: target, on: piece)
            let point = piece.point(at: t)
            let distance = hypot(point.x - target.x, point.y - target.y)
            if distance < best?.distance ?? .infinity {
                best = NearestPoint(segment: index, t: t, point: point, distance: distance)
            }
        }
        return best
    }

    /// How many samples a cubic is cut into before the nearest ones are refined.
    private static let samples = 64

    /// The parameter of a line's point nearest `target`, clamped to the segment.
    private static func projection(of target: PenPoint, on segment: Segment) -> Double {
        let dx = segment.end.x - segment.start.x, dy = segment.end.y - segment.start.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return 0 }
        let t = ((target.x - segment.start.x) * dx + (target.y - segment.start.y) * dy) / length
        return min(max(t, 0), 1)
    }

    /// The parameter of a cubic's point nearest `target`: every sample nearer than its
    /// neighbors, refined by Newton's method, and the nearest of those.
    private static func nearestParameter(to target: PenPoint, on segment: Segment) -> Double {
        let squared = { (t: Double) -> Double in
            let p = segment.point(at: t)
            return (p.x - target.x) * (p.x - target.x) + (p.y - target.y) * (p.y - target.y)
        }
        let distances = (0 ... samples).map { squared(Double($0) / Double(samples)) }
        var bestT = 0.0
        var bestDistance = Double.infinity
        for index in 0 ... samples {
            let isLocalMinimum = (index == 0 || distances[index] <= distances[index - 1])
                && (index == samples || distances[index] <= distances[index + 1])
            guard isLocalMinimum else { continue }
            // Newton's step can overshoot into a worse basin; the sample itself stands too.
            let sample = Double(index) / Double(samples)
            for t in [sample, refine(sample, toward: target, on: segment)] where squared(t) < bestDistance {
                bestDistance = squared(t)
                bestT = t
            }
        }
        return bestT
    }

    /// Newton's method on the derivative of the squared distance, kept within 0…1.
    private static func refine(_ start: Double, toward target: PenPoint, on segment: Segment) -> Double {
        var t = start
        for _ in 0 ..< 12 {
            let p = segment.point(at: t), d1 = segment.velocity(at: t), d2 = segment.acceleration(at: t)
            let ex = p.x - target.x, ey = p.y - target.y
            let slope = ex * d1.x + ey * d1.y
            let curvature = d1.x * d1.x + d1.y * d1.y + ex * d2.x + ey * d2.y
            guard curvature > 0 else { break }
            let next = min(max(t - slope / curvature, 0), 1)
            if abs(next - t) < 1e-14 { return next }
            t = next
        }
        return t
    }
}
