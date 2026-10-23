//
//  PenConnectionRenderer+Subtree.swift
//  Woodcase
//

import CoreGraphics

extension PenConnectionRenderer {
    /// Draws, over a subtree just rendered into `context`, every top-level connection whose
    /// two anchors both fall inside the area the context shows.
    ///
    /// A connection is a top-level node of its own, so a render of one frame — `render`'s
    /// pages, `shot`'s node — would otherwise never reach the connectors drawn between that
    /// frame's cards. The test is where the anchors are, not which tree the endpoint nodes
    /// sit in: a connector both of whose ends are in the picture belongs in it, and one that
    /// leaves the picture does not.
    ///
    /// The context draws `rootID` at its layout rect — in its parent's coordinates — so the
    /// connections, which are on the canvas, are drawn through the inverse of the parent's
    /// placement; the area shown is the context's clip bounds, mapped to the canvas.
    ///
    /// - Parameters:
    ///   - rootID: The subtree's root, just drawn.
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    ///   - context: The context, in the root's parent's coordinates.
    ///   - overrides: Per-node property overrides, for a connection's opacity or visibility.
    ///   - imageProvider: Resolves an image paint's URL, for an image stroke.
    static func renderConnections(
        over rootID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect],
        into context: CGContext,
        overrides: [String: NodeOverrides],
        imageProvider: PenRenderer.ImageProvider
    ) {
        let connections = document.children.filter { node in
            guard node.id != rootID, case .connection = node.kind else { return false }
            return PenRenderer.isEnabled(node, overrides: overrides[node.id])
        }
        guard !connections.isEmpty,
              let root = PenCanvasRoot.resolve([rootID], in: document, layoutRects: layoutRects).first,
              let toParent = root.parentTransform.inverted()
        else { return }
        let shown = context.boundingBoxOfClipPath
        guard !shown.isNull, !shown.isInfinite else { return }
        let area = root.parentTransform.bounds(of: PenRect(
            x: Double(shown.minX), y: Double(shown.minY), width: Double(shown.width), height: Double(shown.height)
        ))
        let canvasRects = PenLayoutEngine.canvasRects(in: document, layoutRects: layoutRects)

        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(toParent.cgAffineTransform)
        for node in connections {
            guard case let .connection(data) = node.kind, let route = node.connectionRoute(in: canvasRects),
                  let start = route.points.first, let end = route.points.last,
                  inside(start, area), inside(end, area)
            else { continue }
            render(
                node, data: data, opacity: overrides[node.id]?.opacity ?? node.common.opacity?.literalValue,
                canvasRects: canvasRects, in: context, imageProvider: imageProvider
            )
        }
    }

    /// Whether `point` lies inside `rect` or on its edge.
    private static func inside(_ point: PenPoint, _ rect: PenRect) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height
    }
}
