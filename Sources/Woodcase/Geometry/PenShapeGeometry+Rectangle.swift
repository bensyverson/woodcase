import Foundation

extension PenShapeGeometry {
    /// A rectangle's outline: a plain rect, one rounded rect for a uniform radius, or the
    /// edges traced with a tangent arc at each rounded corner.
    ///
    /// Radii are clamped to half the shorter side, as CSS `border-radius` is; beyond it a
    /// corner would turn elliptical and look squashed (a radius of 8 on a bar 8 tall).
    static func rectangle(in rect: PenRect, cornerRadius: PenCornerRadius.Corners?) -> PenShapeOutline {
        guard let corners = cornerRadius, !corners.isUniform || corners.topLeft > 0 else {
            return PenShapeOutline(elements: [.rect(rect)])
        }
        let maxRadius = min(rect.width / 2, rect.height / 2)
        if corners.isUniform {
            return PenShapeOutline(elements: [.roundedRect(rect, cornerRadius: min(corners.topLeft, maxRadius))])
        }

        let tl = min(corners.topLeft, maxRadius)
        let tr = min(corners.topRight, maxRadius)
        let br = min(corners.bottomRight, maxRadius)
        let bl = min(corners.bottomLeft, maxRadius)
        let x = rect.x
        let y = rect.y
        let w = rect.width
        let h = rect.height

        /// The corner itself, rounded toward the next edge when its radius is positive.
        func corner(_ vertex: PenPoint, toward next: PenPoint, radius: Double) -> PenShapeOutline.Element {
            radius > 0
                ? .tangentArc(tangent1End: vertex, tangent2End: next, radius: radius)
                : .command(.line(to: vertex))
        }

        return PenShapeOutline(elements: [
            .command(.move(to: PenPoint(x: x + tl, y: y))),
            .command(.line(to: PenPoint(x: x + w - tr, y: y))),
            corner(PenPoint(x: x + w, y: y), toward: PenPoint(x: x + w, y: y + tr), radius: tr),
            .command(.line(to: PenPoint(x: x + w, y: y + h - br))),
            corner(PenPoint(x: x + w, y: y + h), toward: PenPoint(x: x + w - br, y: y + h), radius: br),
            .command(.line(to: PenPoint(x: x + bl, y: y + h))),
            corner(PenPoint(x: x, y: y + h), toward: PenPoint(x: x, y: y + h - bl), radius: bl),
            .command(.line(to: PenPoint(x: x, y: y + tl))),
            corner(PenPoint(x: x, y: y), toward: PenPoint(x: x + tl, y: y), radius: tl),
            .command(.close),
        ])
    }
}
