import Foundation

extension PenShapeGeometry {
    /// The rule a node's outline is filled and clipped with.
    ///
    /// Even-odd for a path that declares `fillRule: evenodd` and for an ellipse with an
    /// `innerRadius`, whose full-sweep hole is a second subpath (an arc donut is one closed
    /// ring, which either rule fills alike); nonzero for everything else.
    static func fillRule(for node: PenNode) -> PenFillRule {
        switch node.kind {
        case let .ellipse(data):
            if let inner = data.innerRadius?.literalValue, inner > 0 { return .evenodd }
            return .nonzero
        case let .path(data):
            return data.fillRule == .evenodd ? .evenodd : .nonzero
        default:
            return .nonzero
        }
    }
}
