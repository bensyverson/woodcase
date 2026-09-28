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
            addRoundedRect(in: rect.cgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        case let .ellipse(rect):
            addEllipse(in: rect.cgRect)
        }
    }
}
