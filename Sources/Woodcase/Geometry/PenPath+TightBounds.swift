import Foundation

extension PenPath {
    /// The smallest rectangle containing the drawn path, or `nil` when it has no points.
    ///
    /// Unlike a bounding box over every point, control points count only where the curve
    /// actually reaches: each Bézier contributes its endpoints and its parametric extrema.
    public var tightBounds: PenRect? {
        var bounds = Bounds()
        var current = PenPoint.zero
        var subpathStart = PenPoint.zero

        for command in commands {
            switch command {
            case let .move(to):
                bounds.include(to)
                current = to
                subpathStart = to
            case let .line(to):
                bounds.include(to)
                current = to
            case let .quadCurve(to, control):
                bounds.include(to)
                for axis in Axis.allCases {
                    let p0 = axis.value(of: current), p1 = axis.value(of: control), p2 = axis.value(of: to)
                    // B'(t) = 0 at t = (P0 - P1) / (P0 - 2 P1 + P2).
                    let denominator = p0 - 2 * p1 + p2
                    guard abs(denominator) > Self.epsilon else { continue }
                    let t = (p0 - p1) / denominator
                    guard t > Self.epsilon, t < 1 - Self.epsilon else { continue }
                    bounds.include((1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2, on: axis)
                }
                current = to
            case let .cubicCurve(to, control1, control2):
                bounds.include(to)
                for axis in Axis.allCases {
                    let p0 = axis.value(of: current), p1 = axis.value(of: control1)
                    let p2 = axis.value(of: control2), p3 = axis.value(of: to)
                    // B'(t) = 0 is the quadratic a t² + b t + c = 0.
                    let a = -3 * p0 + 9 * p1 - 9 * p2 + 3 * p3
                    let b = 6 * p0 - 12 * p1 + 6 * p2
                    let c = -3 * p0 + 3 * p1
                    for t in Self.roots(a: a, b: b, c: c) where t > Self.epsilon && t < 1 - Self.epsilon {
                        let mt = 1 - t
                        let value = mt * mt * mt * p0 + 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t * p3
                        bounds.include(value, on: axis)
                    }
                }
                current = to
            case .close:
                current = subpathStart
            }
        }
        return bounds.rect
    }

    /// Below this, a coefficient is zero and a parameter is at an endpoint.
    private static let epsilon = 1e-6

    /// The real roots of a t² + b t + c = 0, or of b t + c = 0 when `a` is zero.
    private static func roots(a: Double, b: Double, c: Double) -> [Double] {
        if abs(a) < epsilon {
            guard abs(b) > epsilon else { return [] }
            return [-c / b]
        }
        let discriminant = b * b - 4 * a * c
        guard discriminant >= -epsilon else { return [] }
        let sqrtD = sqrt(max(0, discriminant))
        return [(-b + sqrtD) / (2 * a), (-b - sqrtD) / (2 * a)]
    }

    /// One axis of a point, so a curve's extrema are solved once for both.
    private enum Axis: CaseIterable {
        case x
        case y

        func value(of point: PenPoint) -> Double {
            self == .x ? point.x : point.y
        }
    }

    /// A running minimum and maximum on both axes.
    private struct Bounds {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var hasPoints = false

        mutating func include(_ point: PenPoint) {
            hasPoints = true
            include(point.x, on: .x)
            include(point.y, on: .y)
        }

        mutating func include(_ value: Double, on axis: Axis) {
            switch axis {
            case .x:
                minX = min(minX, value)
                maxX = max(maxX, value)
            case .y:
                minY = min(minY, value)
                maxY = max(maxY, value)
            }
        }

        var rect: PenRect? {
            hasPoints ? PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : nil
        }
    }
}
