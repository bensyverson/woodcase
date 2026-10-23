import Foundation

extension PenSVGPathWriter {
    /// Appends the commands for one outline element: the absolute SVG commands that trace what
    /// the CoreGraphics call of the same name draws.
    mutating func write(_ element: PenShapeOutline.Element) {
        switch element {
        case let .command(command):
            write(command)
        case let .tangentArc(tangent1End, tangent2End, radius):
            tangentArc(tangent1End, tangent2End, radius: radius)
        case let .ellipticalArc(center, radiusX, radiusY, startAngle, endAngle, clockwise):
            ellipticalArc(center: center, rx: radiusX, ry: radiusY, from: startAngle, to: endAngle, clockwise: clockwise)
        case let .rect(rect):
            move(PenPoint(x: rect.x, y: rect.y))
            line(PenPoint(x: rect.maxX, y: rect.y))
            line(PenPoint(x: rect.maxX, y: rect.maxY))
            line(PenPoint(x: rect.x, y: rect.maxY))
            close()
        case let .roundedRect(rect, radius):
            roundedRect(rect, radius: radius)
        case let .ellipse(rect):
            let center = PenPoint(x: rect.midX, y: rect.midY)
            let (rx, ry) = (rect.width / 2, rect.height / 2)
            move(PenPoint(x: rect.maxX, y: center.y))
            arc(rx: rx, ry: ry, large: true, sweep: true, to: PenPoint(x: rect.x, y: center.y))
            arc(rx: rx, ry: ry, large: true, sweep: true, to: PenPoint(x: rect.maxX, y: center.y))
            close()
        }
    }

    /// Moves to `point` when there is no current point, otherwise draws a line to it
    /// unless already there — how CoreGraphics leads into an arc.
    private mutating func lead(to point: PenPoint) {
        guard let current else {
            move(point)
            return
        }
        if current != point { line(point) }
    }

    /// An SVG arc: `large` is the large-arc flag, `sweep` the sweep flag — the direction of
    /// increasing angle, clockwise on a y-down screen.
    private mutating func arc(rx: Double, ry: Double, large: Bool, sweep: Bool, to point: PenPoint) {
        commands.append("A\(number(rx)) \(number(ry)) 0 \(large ? 1 : 0) \(sweep ? 1 : 0) \(pair(point))")
        current = point
    }

    /// `addArc(center:radius:startAngle:endAngle:clockwise:transform:)` on the unit circle,
    /// scaled by the radii: CoreGraphics' `clockwise` runs the angle *down*, which on a
    /// y-down screen is SVG's sweep flag 0.
    private mutating func ellipticalArc(center: PenPoint, rx: Double, ry: Double, from start: Double, to end: Double, clockwise: Bool) {
        let point = { (angle: Double) in PenPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle)) }
        lead(to: point(start))
        let turn = 2 * Double.pi
        var extent = (clockwise ? start - end : end - start).truncatingRemainder(dividingBy: turn)
        if extent < 0 { extent += turn }
        guard extent > 1e-12 else { return }
        if turn - extent < 1e-9 {
            // A whole turn cannot be one SVG arc: go halfway round, then the rest.
            let half = clockwise ? start - .pi : start + .pi
            arc(rx: rx, ry: ry, large: true, sweep: !clockwise, to: point(half))
            arc(rx: rx, ry: ry, large: true, sweep: !clockwise, to: point(start))
            return
        }
        arc(rx: rx, ry: ry, large: extent > .pi, sweep: !clockwise, to: point(end))
    }

    /// `addArc(tangent1End:tangent2End:radius:)`: a line to the first tangent point, then
    /// the circular arc of `radius` tangent to both lines; a straight line to
    /// `tangent1End` when the lines are collinear or the radius is zero.
    private mutating func tangentArc(_ corner: PenPoint, _ next: PenPoint, radius: Double) {
        guard let from = current else {
            move(corner)
            return
        }
        let incoming = unit(from.x - corner.x, from.y - corner.y)
        let outgoing = unit(next.x - corner.x, next.y - corner.y)
        let cosine = incoming.x * outgoing.x + incoming.y * outgoing.y
        let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
        guard radius > 0, abs(cross) > 1e-12 else {
            lead(to: corner)
            return
        }
        let halfAngle = acos(max(-1, min(1, cosine))) / 2
        let reach = radius / tan(halfAngle)
        let start = PenPoint(x: corner.x + incoming.x * reach, y: corner.y + incoming.y * reach)
        let end = PenPoint(x: corner.x + outgoing.x * reach, y: corner.y + outgoing.y * reach)
        lead(to: start)
        // The path travels along −incoming and turns onto `outgoing`; that turn is clockwise
        // on a y-down screen when (−incoming) × outgoing is positive, i.e. when `cross` is negative.
        arc(rx: radius, ry: radius, large: false, sweep: cross < 0, to: end)
    }

    private func unit(_ x: Double, _ y: Double) -> PenPoint {
        let length = (x * x + y * y).squareRoot()
        return length > 0 ? PenPoint(x: x / length, y: y / length) : PenPoint(x: 0, y: 0)
    }

    /// `addRoundedRect(in:cornerWidth:cornerHeight:)` with one radius, from the top edge.
    private mutating func roundedRect(_ rect: PenRect, radius: Double) {
        let r = min(radius, rect.width / 2, rect.height / 2)
        move(PenPoint(x: rect.x + r, y: rect.y))
        line(PenPoint(x: rect.maxX - r, y: rect.y))
        arc(rx: r, ry: r, large: false, sweep: true, to: PenPoint(x: rect.maxX, y: rect.y + r))
        line(PenPoint(x: rect.maxX, y: rect.maxY - r))
        arc(rx: r, ry: r, large: false, sweep: true, to: PenPoint(x: rect.maxX - r, y: rect.maxY))
        line(PenPoint(x: rect.x + r, y: rect.maxY))
        arc(rx: r, ry: r, large: false, sweep: true, to: PenPoint(x: rect.x, y: rect.maxY - r))
        line(PenPoint(x: rect.x, y: rect.y + r))
        arc(rx: r, ry: r, large: false, sweep: true, to: PenPoint(x: rect.x + r, y: rect.y))
        close()
    }
}
