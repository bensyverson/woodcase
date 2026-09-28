import CoreGraphics

extension PenFillRule {
    /// The CoreGraphics fill rule of the same name.
    var cgFillRule: CGPathFillRule {
        switch self {
        case .nonzero: .winding
        case .evenodd: .evenOdd
        }
    }
}
