import Foundation

/// An SVG elliptical arc in endpoint form, resolved to cubic Béziers.
///
/// Follows the W3C SVG 1.1 implementation notes (Appendix F.6): out-of-range radii are
/// corrected, the endpoint form is converted to a center and angles, and the sweep is split
/// into segments of at most 90°, each approximated by one cubic.
struct PenSVGArc: Friendly {
    /// The current point the arc starts from.
    var from: PenPoint
    /// The arc's endpoint.
    var to: PenPoint
    /// The ellipse's horizontal radius before rotation; non-negative.
    var radiusX: Double
    /// The ellipse's vertical radius before rotation; non-negative.
    var radiusY: Double
    /// The ellipse's x-axis rotation, in degrees.
    var rotation: Double
    /// Whether the arc takes the longer of the two ways round.
    var largeArc: Bool
    /// Whether the arc runs in the positive-angle direction (clockwise on a y-down screen).
    var sweep: Bool

    /// The arc as commands: nothing when it ends where it starts, a line when a radius is
    /// zero, otherwise one cubic per segment of at most 90°.
    var commands: [PenPathCommand] {
        guard from != to else { return [] }
        guard radiusX > 0, radiusY > 0 else { return [.line(to: to)] }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // F.6.5.1: the midpoint, in the ellipse's unrotated frame.
        let dx = (from.x - to.x) / 2
        let dy = (from.y - to.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // F.6.6: radii too small to span the endpoints are scaled up until they just do.
        var rx = radiusX
        var ry = radiusY
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p
        let lambda = x1pSq / (rx * rx) + y1pSq / (ry * ry)
        if lambda > 1 {
            let sqrtLambda = sqrt(lambda)
            rx *= sqrtLambda
            ry *= sqrtLambda
        }
        let rxSq = rx * rx
        let rySq = ry * ry

        // F.6.5.2: the center, in the unrotated frame.
        var sq = (rxSq * rySq - rxSq * y1pSq - rySq * x1pSq) / (rxSq * y1pSq + rySq * x1pSq)
        if sq < 0 { sq = 0 }
        var root = sqrt(sq)
        if largeArc == sweep { root = -root }
        let cxp = root * rx * y1p / ry
        let cyp = -root * ry * x1p / rx

        // F.6.5.3: the center, in drawing space.
        let cx = cosPhi * cxp - sinPhi * cyp + (from.x + to.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (from.y + to.y) / 2

        // F.6.5.5–6: the start angle and the sweep.
        let theta1 = Self.angle(ux: 1, uy: 0, vx: (x1p - cxp) / rx, vy: (y1p - cyp) / ry)
        var dtheta = Self.angle(
            ux: (x1p - cxp) / rx, uy: (y1p - cyp) / ry,
            vx: (-x1p - cxp) / rx, vy: (-y1p - cyp) / ry
        )
        if !sweep, dtheta > 0 {
            dtheta -= 2 * .pi
        } else if sweep, dtheta < 0 {
            dtheta += 2 * .pi
        }

        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let segmentAngle = dtheta / Double(segments)
        let ellipse = Ellipse(cx: cx, cy: cy, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi)
        return (0 ..< segments).map { i in
            ellipse.cubic(from: theta1 + Double(i) * segmentAngle, sweeping: segmentAngle)
        }
    }

    /// The signed angle from vector u to vector v.
    private static func angle(ux: Double, uy: Double, vx: Double, vy: Double) -> Double {
        let dot = ux * vx + uy * vy
        let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
        // Rounding can push the ratio just past ±1, where acos is NaN.
        let ratio = max(-1, min(1, dot / length))
        let angle = acos(ratio)
        return ux * vy - uy * vx < 0 ? -angle : angle
    }

    /// The resolved ellipse an arc runs along.
    private struct Ellipse: Friendly {
        let cx: Double
        let cy: Double
        let rx: Double
        let ry: Double
        let cosPhi: Double
        let sinPhi: Double

        /// One cubic approximating the arc from `theta1` over `dtheta` (at most 90°).
        func cubic(from theta1: Double, sweeping dtheta: Double) -> PenPathCommand {
            let alpha = sin(dtheta) * (sqrt(4 + 3 * pow(tan(dtheta / 2), 2)) - 1) / 3
            let cosTheta1 = cos(theta1)
            let sinTheta1 = sin(theta1)
            let cosTheta2 = cos(theta1 + dtheta)
            let sinTheta2 = sin(theta1 + dtheta)

            let p1x = cx + cosPhi * rx * cosTheta1 - sinPhi * ry * sinTheta1
            let p1y = cy + sinPhi * rx * cosTheta1 + cosPhi * ry * sinTheta1
            let p2x = cx + cosPhi * rx * cosTheta2 - sinPhi * ry * sinTheta2
            let p2y = cy + sinPhi * rx * cosTheta2 + cosPhi * ry * sinTheta2

            // The tangents at both ends, before rotation.
            let d1x = -rx * sinTheta1
            let d1y = ry * cosTheta1
            let d2x = -rx * sinTheta2
            let d2y = ry * cosTheta2

            return .cubicCurve(
                to: PenPoint(x: p2x, y: p2y),
                control1: PenPoint(
                    x: p1x + alpha * (cosPhi * d1x - sinPhi * d1y),
                    y: p1y + alpha * (sinPhi * d1x + cosPhi * d1y)
                ),
                control2: PenPoint(
                    x: p2x - alpha * (cosPhi * d2x - sinPhi * d2y),
                    y: p2y - alpha * (sinPhi * d2x + cosPhi * d2y)
                )
            )
        }
    }
}
