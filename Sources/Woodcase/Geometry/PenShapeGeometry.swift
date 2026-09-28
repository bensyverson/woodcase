import Foundation

/// Computes the outline of each .pen shape type as a ``PenShapeOutline``, without CoreGraphics.
///
/// The one place the shape of a node is decided. The CoreGraphics renderer draws the
/// outline through `PenShapeBuilder`; a code emitter can write the same outline as code.
enum PenShapeGeometry {
    /// The shape type to outline, with its parameters.
    enum Shape: Friendly {
        /// A rectangle, rounded by the corner radii passed beside it.
        case rectangle
        /// An ellipse; with a partial sweep a pie slice, with an inner radius a ring or an
        /// arc donut. Angles are in degrees, counter-clockwise from the right; the inner
        /// radius is a fraction of the outer.
        case ellipse(startAngle: Double? = nil, sweepAngle: Double? = nil, innerRadius: Double? = nil)
        /// A regular polygon inscribed in the box, its first vertex at the top.
        case polygon(count: Int, cornerRadius: Double? = nil)
        /// A line from the box's top-left corner to its bottom-right.
        case line
        /// SVG path geometry, mapped onto the box through its viewBox or its tight bounds.
        case path(geometry: String?, viewBox: PenViewBox? = nil, fillRule: PenFillRule = .nonzero)
    }

    /// The outline of a shape within a box.
    ///
    /// - Parameters:
    ///   - shape: The shape type and its parameters.
    ///   - rect: The node's box. A negative width or height is read as CoreGraphics reads it.
    ///   - cornerRadius: The corner radii, for rectangles.
    /// - Returns: The outline, or `nil` for a polygon of fewer than three sides or a path
    ///   whose geometry is missing or does not parse.
    static func outline(
        for shape: Shape,
        rect: PenRect,
        cornerRadius: PenCornerRadius.Corners? = nil
    ) -> PenShapeOutline? {
        let box = rect.standardized
        switch shape {
        case .rectangle:
            return rectangle(in: box, cornerRadius: cornerRadius)
        case let .ellipse(startAngle, sweepAngle, innerRadius):
            return ellipse(in: box, startAngle: startAngle, sweepAngle: sweepAngle, innerRadius: innerRadius)
        case let .polygon(count, polygonCornerRadius):
            return polygon(in: box, sides: count, cornerRadius: polygonCornerRadius)
        case .line:
            return PenShapeOutline(elements: [
                .command(.move(to: PenPoint(x: box.x, y: box.y))),
                .command(.line(to: PenPoint(x: box.maxX, y: box.maxY))),
            ])
        case let .path(geometry, viewBox, _):
            guard let geometry, let path = PenPath(svg: geometry) else { return nil }
            return PenShapeOutline(elements: path.mapped(onto: box, viewBox: viewBox).commands.map { .command($0) })
        }
    }

    /// The outline of a node within its box, or `nil` for a node kind with no shape.
    static func outline(for node: PenNode, rect: PenRect) -> PenShapeOutline? {
        switch node.kind {
        case let .rectangle(data):
            outline(for: .rectangle, rect: rect, cornerRadius: data.cornerRadius?.resolve())
        case let .frame(data):
            outline(for: .rectangle, rect: rect, cornerRadius: data.cornerRadius?.resolve())
        case let .browser(data):
            outline(for: .rectangle, rect: rect, cornerRadius: data.cornerRadius?.resolve())
        case let .ellipse(data):
            outline(
                for: .ellipse(
                    startAngle: data.startAngle?.literalValue,
                    sweepAngle: data.sweepAngle?.literalValue,
                    innerRadius: data.innerRadius?.literalValue
                ),
                rect: rect
            )
        case let .polygon(data):
            outline(
                for: .polygon(
                    count: data.polygonCount?.literalValue.map { Int($0) } ?? defaultPolygonCount,
                    cornerRadius: data.cornerRadius?.resolve()?.topLeft
                ),
                rect: rect
            )
        case .line:
            outline(for: .line, rect: rect)
        case let .path(data):
            outline(
                for: .path(geometry: data.geometry, viewBox: data.viewBox, fillRule: data.fillRule ?? .nonzero),
                rect: rect
            )
        default:
            nil
        }
    }

    /// The number of sides of a polygon that does not declare one.
    static let defaultPolygonCount = 6
}
