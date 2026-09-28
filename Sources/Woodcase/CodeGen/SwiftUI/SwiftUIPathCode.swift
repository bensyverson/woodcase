//
//  SwiftUIPathCode.swift
//  Woodcase
//

import Foundation

/// A ``PenShapeOutline`` as SwiftUI `Path` calls: one statement per element, each the
/// call of the same name the Core Graphics renderer makes, on a variable named `path`.
enum SwiftUIPathCode {
    /// The statements that draw `outline` into `path`.
    static func statements(_ outline: PenShapeOutline) -> [String] {
        outline.elements.map(statement)
    }

    private static func statement(_ element: PenShapeOutline.Element) -> String {
        switch element {
        case let .command(command):
            switch command {
            case let .move(to): "path.move(to: \(point(to)))"
            case let .line(to): "path.addLine(to: \(point(to)))"
            case let .quadCurve(to, control): "path.addQuadCurve(to: \(point(to)), control: \(point(control)))"
            case let .cubicCurve(to, control1, control2):
                "path.addCurve(to: \(point(to)), control1: \(point(control1)), control2: \(point(control2)))"
            case .close: "path.closeSubpath()"
            }
        case let .tangentArc(tangent1End, tangent2End, radius):
            "path.addArc(tangent1End: \(point(tangent1End)), tangent2End: \(point(tangent2End)), radius: \(number(radius)))"
        case let .ellipticalArc(center, radiusX, radiusY, startAngle, endAngle, clockwise):
            "path.addArc(center: .zero, radius: 1, startAngle: .radians(\(number(startAngle))), "
                + "endAngle: .radians(\(number(endAngle))), clockwise: \(clockwise), "
                + "transform: CGAffineTransform(translationX: \(number(center.x)), y: \(number(center.y)))"
                + ".scaledBy(x: \(number(radiusX)), y: \(number(radiusY))))"
        case let .rect(rect):
            "path.addRect(\(self.rect(rect)))"
        case let .roundedRect(rect, cornerRadius):
            "path.addRoundedRect(in: \(self.rect(rect)), cornerSize: CGSize(width: \(number(cornerRadius)), height: \(number(cornerRadius))), style: .circular)"
        case let .ellipse(rect):
            "path.addEllipse(in: \(self.rect(rect)))"
        }
    }

    /// A `CGPoint` literal.
    static func point(_ point: PenPoint) -> String {
        "CGPoint(x: \(number(point.x)), y: \(number(point.y)))"
    }

    /// A `CGRect` literal.
    static func rect(_ rect: PenRect) -> String {
        "CGRect(x: \(number(rect.x)), y: \(number(rect.y)), width: \(number(rect.width)), height: \(number(rect.height)))"
    }

    /// A coordinate rounded to a millionth of a point, so trigonometry reads `186.60254`
    /// and a zero never reads `-0`.
    static func number(_ value: Double) -> String {
        let rounded = (value * 1_000_000).rounded() / 1_000_000
        return SwiftUILiteral.number(rounded == 0 ? 0 : rounded)
    }
}
