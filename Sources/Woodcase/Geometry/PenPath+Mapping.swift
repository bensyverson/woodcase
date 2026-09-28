import Foundation

public extension PenPath {
    /// The region of the path's own coordinates that is mapped onto a node's box.
    ///
    /// A usable `viewBox` names it. Without one, Pen's default applies: the path's tight
    /// bounds, so the drawn geometry fills the box. `nil` when there is neither.
    func sourceRegion(viewBox: PenViewBox?) -> PenRect? {
        if let viewBox, viewBox.isUsable {
            return PenRect(x: viewBox.x, y: viewBox.y, width: viewBox.width, height: viewBox.height)
        }
        return tightBounds
    }

    /// The path mapped onto a node's box, as Pen draws a `path` node.
    ///
    /// The ``sourceRegion(viewBox:)`` is translated to the box's origin and scaled on each
    /// axis independently to the box's size — SVG's `preserveAspectRatio="none"`. Geometry
    /// outside a viewBox overflows the box. An axis along which the region has no extent (a
    /// horizontal line's height) is translated but not scaled; a path with no points is
    /// returned unchanged.
    func mapped(onto rect: PenRect, viewBox: PenViewBox?) -> PenPath {
        guard let source = sourceRegion(viewBox: viewBox) else { return self }
        let scaleX = source.width > 0 ? rect.width / source.width : 1
        let scaleY = source.height > 0 ? rect.height / source.height : 1
        return PenPath(commands: commands.map { command in
            command.mappingPoints { point in
                PenPoint(x: rect.x + (point.x - source.x) * scaleX, y: rect.y + (point.y - source.y) * scaleY)
            }
        })
    }
}
