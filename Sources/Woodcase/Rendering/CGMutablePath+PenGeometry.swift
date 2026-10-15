import CoreGraphics

extension CGMutablePath {
    /// Appends one resolved path command.
    func add(_ command: PenPathCommand) {
        switch command {
        case let .move(to):
            move(to: to.cgPoint)
        case let .line(to):
            addLine(to: to.cgPoint)
        case let .quadCurve(to, control):
            addQuadCurve(to: to.cgPoint, control: control.cgPoint)
        case let .cubicCurve(to, control1, control2):
            addCurve(to: to.cgPoint, control1: control1.cgPoint, control2: control2.cgPoint)
        case .close:
            closeSubpath()
        }
    }

    /// Appends one outline element through the CoreGraphics call it is named for.
    func add(_ element: PenShapeOutline.Element) {
        switch element {
        case let .command(command):
            add(command)
        case let .tangentArc(tangent1End, tangent2End, radius):
            addArc(tangent1End: tangent1End.cgPoint, tangent2End: tangent2End.cgPoint, radius: radius)
        case let .ellipticalArc(center, radiusX, radiusY, startAngle, endAngle, clockwise):
            addArc(
                center: .zero, radius: 1, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise,
                transform: CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: radiusX, y: radiusY)
            )
        case let .rect(rect):
            addRect(rect.cgRect)
        case let .roundedRect(rect, cornerRadius):
            addPinnedRoundedRect(rect.cgRect, radius: cornerRadius)
        case let .ellipse(rect):
            addEllipse(in: rect.cgRect)
        }
    }

    /// Appends a rounded rectangle traced from `(x + r, y)`, clockwise on screen in the
    /// renderer's y-down space — where SVG starts one, and so where a dashed stroke's
    /// pattern starts (Penumbra's `project/2026-10-14-feature-enhancements-plan.md` §1.4).
    /// `addRoundedRect` starts at the right edge's middle, which would move the dashes.
    private func addPinnedRoundedRect(_ rect: CGRect, radius: CGFloat) {
        let r = min(radius, rect.width / 2, rect.height / 2)
        move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        closeSubpath()
    }
}
