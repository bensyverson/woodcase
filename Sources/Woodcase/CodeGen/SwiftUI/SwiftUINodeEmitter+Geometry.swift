//
//  SwiftUINodeEmitter+Geometry.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A path, polygon, line, arc or donut: its outline as a `Shape` the page declares,
    /// filled, shadowed and stroked like any other shape.
    ///
    /// The outline is ``PenShapeGeometry``'s, the one the Core Graphics renderer draws,
    /// written as the `Path` calls of the same names (``SwiftUIPathCode``) at the node's
    /// size and fitted to whatever box the view is given.
    func geometry(_ node: PenNode, in container: Container) -> SwiftUIViewCode {
        guard let shape = geometryOutline(node) else {
            return placeholder(node, in: container)
        }
        switch node.kind {
        case let .path(data):
            return filledShape(node, shape: shape, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: [])
        case let .polygon(data):
            return filledShape(node, shape: shape, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: [])
        case let .line(data):
            return filledShape(node, shape: shape, fills: nil, stroke: data, effects: data.effects, in: container, unemitted: [])
        case let .ellipse(data):
            return filledShape(node, shape: shape, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: [])
        default:
            return placeholder(node, in: container)
        }
    }

    /// The declared shape of a path, polygon, line or arc node, declaring it on first use;
    /// `nil` for any other node, and for one whose outline does not exist — a polygon of
    /// fewer than three sides, a path whose geometry is missing or does not parse.
    func geometryOutline(_ node: PenNode) -> Outline? {
        switch node.kind {
        case .path, .polygon, .line: break
        case let .ellipse(data) where isArc(data): break
        default: return nil
        }
        let evenOdd = PenShapeGeometry.fillRule(for: node) == .evenodd
        if let name = shapes.name(forNode: node.id) {
            return Outline(view: "\(name)()", argument: "\(name)()", evenOdd: evenOdd)
        }
        let width = declaredSizing(node, axis: .width).fixedValue
        let height = declaredSizing(node, axis: .height).fixedValue
        let natural = naturalSize(node)
        let size = (width: width ?? natural.width, height: height ?? natural.height)
        let box = PenRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let outline = PenShapeGeometry.outline(for: node, rect: box) else { return nil }
        let label = node.common.name ?? node.id
        let name = shapes.declare(nodeID: node.id, label: label) { name in
            let fitted = "CGSize(width: \(SwiftUIPathCode.number(size.width)), height: \(SwiftUIPathCode.number(size.height)))"
            return [
                "/// The \(SwiftUILiteral.string(label)) \(node.kind.typeName)'s outline, drawn at "
                    + "\(SwiftUIPathCode.number(size.width)) × \(SwiftUIPathCode.number(size.height)) and fitted to the box it is offered.",
                "private struct \(name): Shape {",
                "    func path(in rect: CGRect) -> Path {",
                "        var path = Path()",
            ] + SwiftUIPathCode.statements(outline).map { "        \($0)" } + [
                "        return path.penFitted(from: \(fitted), to: rect)",
                "    }",
                "}",
            ]
        }
        return Outline(view: "\(name)()", argument: "\(name)()", evenOdd: evenOdd)
    }

    /// The size a node's outline is drawn at when its box is not a fixed size: a path's
    /// geometry at its own size, anything else a 100-point square. The view fits it to
    /// its box, so only a rounded polygon's corners depend on the choice.
    private func naturalSize(_ node: PenNode) -> (width: Double, height: Double) {
        if case let .path(data) = node.kind, let geometry = data.geometry, let path = PenPath(svg: geometry),
           let region = path.sourceRegion(viewBox: data.viewBox)
        {
            return (region.width, region.height)
        }
        return (Self.defaultShapeSize, Self.defaultShapeSize)
    }

    /// The side of the square a shape without a fixed size is drawn in.
    private static let defaultShapeSize = 100.0
}
