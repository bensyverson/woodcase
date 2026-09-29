import Foundation

extension PenShapeGeometry {
    /// A regular polygon's outline, inscribed in the box with its first vertex at the top.
    ///
    /// With a positive corner radius each vertex is rounded by a tangent arc toward the
    /// midpoint of the edge after it; the outline starts along the first edge, where the
    /// first vertex's rounding would end.
    ///
    /// - Returns: `nil` for fewer than three sides.
    static func polygon(in rect: PenRect, sides: Int, cornerRadius: Double?) -> PenShapeOutline? {
        guard sides >= 3 else { return nil }

        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        let angleStep = 2 * Double.pi / Double(sides)

        func vertex(_ i: Int) -> PenPoint {
            polygonVertex(i, cx: cx, cy: cy, rx: rx, ry: ry, angleStep: angleStep)
        }

        guard let radius = cornerRadius, radius > 0 else {
            let points = (0 ..< sides).map(vertex)
            return PenShapeOutline(
                elements: [.command(.move(to: points[0]))]
                    + points.dropFirst().map { .command(.line(to: $0)) }
                    + [.command(.close)]
            )
        }

        var elements: [PenShapeOutline.Element] = []
        for i in 0 ..< sides {
            let current = vertex(i)
            let next = vertex(i + 1)
            let after = vertex(i + 2)
            if i == 0 {
                let ratio = min(radius / distance(current, next), 0.5)
                elements.append(.command(.move(to: PenPoint(
                    x: current.x + (next.x - current.x) * ratio,
                    y: current.y + (next.y - current.y) * ratio
                ))))
            }
            elements.append(.tangentArc(
                tangent1End: next,
                tangent2End: PenPoint(x: (next.x + after.x) / 2, y: (next.y + after.y) / 2),
                radius: radius
            ))
        }
        elements.append(.command(.close))
        return PenShapeOutline(elements: elements)
    }

    /// A regular polygon's vertices inscribed in the box, the first at the top, in drawing
    /// order — the corners ``polygon(in:sides:cornerRadius:)`` draws.
    ///
    /// - Returns: `nil` for fewer than three sides.
    static func polygonVertices(in rect: PenRect, sides: Int) -> [PenPoint]? {
        guard sides >= 3 else { return nil }
        let angleStep = 2 * Double.pi / Double(sides)
        return (0 ..< sides).map { i in
            polygonVertex(i, cx: rect.midX, cy: rect.midY, rx: rect.width / 2, ry: rect.height / 2, angleStep: angleStep)
        }
    }

    /// The `i`th vertex of a regular polygon on the ellipse centered at `(cx, cy)` with radii
    /// `rx` × `ry`; Pen's first vertex is at the top.
    private static func polygonVertex(
        _ i: Int, cx: Double, cy: Double, rx: Double, ry: Double, angleStep: Double
    ) -> PenPoint {
        let angle = -Double.pi / 2 + angleStep * Double(i)
        return PenPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
    }

    private static func distance(_ a: PenPoint, _ b: PenPoint) -> Double {
        sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
    }
}
