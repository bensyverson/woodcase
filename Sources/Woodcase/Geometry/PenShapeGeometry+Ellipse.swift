import Foundation

extension PenShapeGeometry {
    /// An ellipse's outline: the whole ellipse, a ring, a pie slice or an arc donut.
    ///
    /// Angles are Pen's — degrees counter-clockwise from the right — and become radians in
    /// the y-down drawing space, where the sign flips. Each arc is drawn on the unit circle
    /// and scaled onto the ellipse, so an angle is the ellipse's parametric angle, as Pen
    /// measures it.
    static func ellipse(
        in rect: PenRect,
        startAngle: Double?,
        sweepAngle: Double?,
        innerRadius: Double?
    ) -> PenShapeOutline {
        let sweep = sweepAngle ?? 360
        let start = startAngle ?? 0
        let inner = innerRadius ?? 0

        if abs(sweep) >= 360, inner <= 0 {
            return PenShapeOutline(elements: [.ellipse(in: rect)])
        }

        let rx = rect.width / 2
        let ry = rect.height / 2
        if abs(sweep) >= 360 {
            // A ring: the hole is a second subpath, left open by the even-odd rule.
            return PenShapeOutline(elements: [
                .ellipse(in: rect),
                .ellipse(in: rect.insetBy(dx: rx * (1 - inner), dy: ry * (1 - inner))),
            ])
        }

        let center = PenPoint(x: rect.midX, y: rect.midY)
        let startRadians = -start * .pi / 180
        let endRadians = -(start + sweep) * .pi / 180
        let outerArc = PenShapeOutline.Element.ellipticalArc(
            center: center, radiusX: rx, radiusY: ry,
            startAngle: startRadians, endAngle: endRadians, clockwise: sweep > 0
        )

        guard inner > 0 else {
            // A pie slice: the arc, closed through the center.
            return PenShapeOutline(elements: [.command(.move(to: center)), outerArc, .command(.close)])
        }
        // An arc donut: one closed ring — the outer arc over the sweep, a straight cut along
        // the end angle, the inner arc back over the same sweep, and a straight cut home. The
        // inner ellipse is never drawn outside the sweep.
        return PenShapeOutline(elements: [
            outerArc,
            .ellipticalArc(
                center: center, radiusX: rx * inner, radiusY: ry * inner,
                startAngle: endRadians, endAngle: startRadians, clockwise: sweep <= 0
            ),
            .command(.close),
        ])
    }
}
