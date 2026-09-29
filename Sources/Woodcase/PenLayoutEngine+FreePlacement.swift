//
//  PenLayoutEngine+FreePlacement.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// Where a node placed by its own `x`/`y` lands: the bounds of its box turned and
    /// flipped about that anchor.
    ///
    /// Pen turns and flips a node its parent does not lay out — a root, a child of a
    /// `layout: "none"` frame or of a group, or an absolutely positioned child of a flex
    /// frame — about its top-left corner, flipping first, and its layout reports the bounds
    /// of the result. So the rect is the turned bounding box moved by where the transform
    /// sends the box's leftmost and topmost corners: a 200×60 rectangle at `(80, 60)` turned
    /// by −20° lands at `(59.48, 60)`, 60 × sin 20° left of its anchor, and a `flipX` node
    /// lands its whole width left of it. The renderer draws the unturned box centered in this
    /// rect and turns it about the center, which is the same picture as turning it about the
    /// anchor. A node in a flex flow is not placed here: Pen grows its slot to the turned
    /// bounds (``applyRotationExpansion(width:height:node:)``).
    ///
    /// This is the box at the anchor, which is every node's box but a group's; place a group
    /// with ``freeRect(of:x:y:box:)``.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - x: Its anchor's `x`, in its parent's space.
    ///   - y: Its anchor's `y`.
    ///   - width: Its unturned width.
    ///   - height: Its unturned height.
    /// - Returns: Its layout rect, in its parent's space, carrying the unturned size as its
    ///   ``PenRect/unturnedSize`` when the node turns.
    public static func freeRect(of node: PenNode, x: Double, y: Double, width: Double, height: Double) -> PenRect {
        freeRect(of: node, x: x, y: y, box: PenRect(x: 0, y: 0, width: width, height: height))
    }

    /// Where a node placed by its own `x`/`y` lands, given its unturned box in its own
    /// coordinates: the bounds of that box turned and flipped about the anchor.
    ///
    /// Every node's box starts at its anchor except a group's. A group has no box of its own:
    /// its `x`/`y` is the origin its children are placed from, and its box is their union
    /// (``groupBox(of:in:)``), which starts wherever the children do — left of and above the
    /// anchor when they reach there. Pen settles a group at `(60, 10)` whose turned child
    /// reaches 11.96 above it at `y` −1.96 (`render-free-groups.pen`).
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - x: Its anchor's `x`, in its parent's space.
    ///   - y: Its anchor's `y`.
    ///   - box: Its unturned box, measured from the anchor.
    /// - Returns: Its layout rect, in its parent's space, carrying the box's size as its
    ///   ``PenRect/unturnedSize`` when the node turns.
    public static func freeRect(of node: PenNode, x: Double, y: Double, box: PenRect) -> PenRect {
        let rotation = node.common.rotation?.literalValue ?? 0
        let flipX = node.common.flipX?.literalValue == true
        let flipY = node.common.flipY?.literalValue == true
        guard rotation != 0 || flipX || flipY else {
            return PenRect(x: x + box.x, y: y + box.y, width: box.width, height: box.height)
        }
        let bounds = anchoredBounds(of: box, rotationDegrees: rotation, flipX: flipX, flipY: flipY)
        return PenRect(
            x: x + bounds.x, y: y + bounds.y, width: bounds.width, height: bounds.height,
            unturnedSize: rotation == 0 ? nil : PenSize(width: box.width, height: box.height)
        )
    }

    /// Where a node placed by its own `x`/`y` lands, once the walk has sized it and written
    /// its descendants' rects into `rects`: a group's box is read from its children's rects
    /// there, every other node's is its size at the anchor.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - x: Its anchor's `x`, in its parent's space.
    ///   - y: Its anchor's `y`.
    ///   - size: Its unturned size, as the walk sized it.
    ///   - rects: The map its children's rects were written to.
    /// - Returns: Its layout rect, in its parent's space.
    static func freeRect(
        of node: PenNode, x: Double, y: Double, size: (width: Double, height: Double), placedIn rects: [String: PenRect]
    ) -> PenRect {
        if case .group = node.kind {
            return freeRect(of: node, x: x, y: y, box: groupBox(of: node, in: rects))
        }
        return freeRect(of: node, x: x, y: y, width: size.width, height: size.height)
    }

    /// The bounds of `box` flipped, then turned counter-clockwise by `rotationDegrees`,
    /// about the origin of the coordinates it is measured in.
    ///
    /// The transform is the renderer's (``PenTransformBuilder``) about a different pivot: in
    /// the y-down canvas, Pen's counter-clockwise degrees are a rotation by their negation.
    ///
    /// - Parameters:
    ///   - box: The box, measured from the pivot.
    ///   - rotationDegrees: Pen's rotation, counter-clockwise.
    ///   - flipX: Whether the box is mirrored left to right.
    ///   - flipY: Whether the box is mirrored top to bottom.
    /// - Returns: The bounds, measured from the pivot.
    static func anchoredBounds(of box: PenRect, rotationDegrees: Double, flipX: Bool, flipY: Bool) -> PenRect {
        let radians = -rotationDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let signX = flipX ? -1.0 : 1.0
        let signY = flipY ? -1.0 : 1.0
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for cornerX in [box.x, box.x + box.width] {
            for cornerY in [box.y, box.y + box.height] {
                let flippedX = cornerX * signX
                let flippedY = cornerY * signY
                let turnedX = flippedX * cosine - flippedY * sine
                let turnedY = flippedX * sine + flippedY * cosine
                minX = min(minX, turnedX)
                maxX = max(maxX, turnedX)
                minY = min(minY, turnedY)
                maxY = max(maxY, turnedY)
            }
        }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
