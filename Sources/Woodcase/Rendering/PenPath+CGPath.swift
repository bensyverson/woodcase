import CoreGraphics

public extension PenPath {
    /// The path as a CoreGraphics path, one element per command.
    var cgPath: CGPath {
        let path = CGMutablePath()
        for command in commands {
            path.add(command)
        }
        return path
    }

    /// Reads a CoreGraphics path's elements as commands.
    init(_ cgPath: CGPath) {
        var commands: [PenPathCommand] = []
        cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                commands.append(.move(to: PenPoint(points[0])))
            case .addLineToPoint:
                commands.append(.line(to: PenPoint(points[0])))
            case .addQuadCurveToPoint:
                commands.append(.quadCurve(to: PenPoint(points[1]), control: PenPoint(points[0])))
            case .addCurveToPoint:
                commands.append(.cubicCurve(
                    to: PenPoint(points[2]), control1: PenPoint(points[0]), control2: PenPoint(points[1])
                ))
            case .closeSubpath:
                commands.append(.close)
            @unknown default:
                break
            }
        }
        self.init(commands: commands)
    }
}
