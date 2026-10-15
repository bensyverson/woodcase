import Foundation

extension PenShapeGeometry {
    /// A regular polygon's outline, inscribed in the box with its first vertex at the top.
    ///
    /// With a positive corner radius each vertex is rounded by a tangent arc toward the
    /// midpoint of the edge after it; the outline starts on the first edge, exactly where
    /// the first vertex's rounding ends — the outline closes onto its start, and a dashed
    /// stroke's pattern starts there.
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
                elements.append(.command(.move(to: roundingEnd(at: current, from: vertex(sides - 1), toward: next, radius: radius))))
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

    /// Where a tangent arc of `radius` rounding `vertex` meets the edge toward `next`: the
    /// arc's tangent point, `radius / tan(θ / 2)` along that edge for the corner's angle θ.
    private static func roundingEnd(at vertex: PenPoint, from previous: PenPoint, toward next: PenPoint, radius: Double) -> PenPoint {
        let toNext = (x: next.x - vertex.x, y: next.y - vertex.y)
        let toPrevious = (x: previous.x - vertex.x, y: previous.y - vertex.y)
        let lengthNext = (toNext.x * toNext.x + toNext.y * toNext.y).squareRoot()
        let lengthPrevious = (toPrevious.x * toPrevious.x + toPrevious.y * toPrevious.y).squareRoot()
        guard lengthNext > 0, lengthPrevious > 0 else { return vertex }
        let cosine = (toNext.x * toPrevious.x + toNext.y * toPrevious.y) / (lengthNext * lengthPrevious)
        let angle = acos(max(-1, min(1, cosine)))
        let along = radius / tan(angle / 2)
        return PenPoint(x: vertex.x + toNext.x / lengthNext * along, y: vertex.y + toNext.y / lengthNext * along)
    }
}
