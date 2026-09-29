import CoreGraphics

extension PenRenderer {
    /// Whether a node is drawn at all: an animation override of `enabled` wins over the
    /// node's own value.
    static func isEnabled(_ node: PenNode, overrides: NodeOverrides?) -> Bool {
        if let enabled = overrides?.enabled { return enabled }
        return node.common.enabled?.literalValue != false
    }

    /// Moves the context into a node's own space: saves the graphics state, then translates
    /// to the node's position and applies its rotation and flip.
    ///
    /// The caller restores the graphics state once the node is drawn.
    ///
    /// - Parameters:
    ///   - ref: The node.
    ///   - layoutRects: Layout rects, keyed by node ID, relative to the parent.
    ///   - overrides: The node's animation overrides.
    ///   - context: The context to move.
    /// - Returns: The node's draw rect in its own space: its unturned box, zero-origin for
    ///   every node but a group, whose box is its children's union measured from its anchor;
    ///   `nil`, with the context untouched, for a node that has no layout rect.
    static func enter(
        _ ref: NodeRef,
        layoutRects: [String: PenRect],
        overrides: NodeOverrides?,
        in context: CGContext
    ) -> PenRect? {
        guard let originalRect = layoutRects[ref.node.id] else { return nil }
        let rect = overridden(originalRect, of: ref.node, by: overrides)

        context.saveGState()

        // A node's content is drawn at its unturned box, centered in its layout rect — the
        // bounds of the turned box — and turned and flipped about that center. For a node
        // placed by its own x/y the layout has already moved the bounds to where turning
        // about the anchor puts them, so the center pivot lands exactly there. A group's box
        // is its children's union, which need not start at its anchor: the context then moves
        // to the anchor, the origin its children's rects are measured from.
        let box = PenLayoutEngine.unturnedBox(of: ref.node, rect: rect, layoutRects: layoutRects)
        context.translateBy(
            x: CGFloat(rect.x + (rect.width - box.width) / 2),
            y: CGFloat(rect.y + (rect.height - box.height) / 2)
        )
        applyTransform(
            ref: ref, drawRect: PenRect(x: 0, y: 0, width: box.width, height: box.height),
            rotationOverride: overrides?.rotation, in: context
        )
        if box.x != 0 || box.y != 0 {
            context.translateBy(x: CGFloat(-box.x), y: CGFloat(-box.y))
        }
        return box
    }

    /// A node's layout rect with an animation's position and size overrides applied.
    ///
    /// A size override is the node's own width or height. An unturned node's rect is that
    /// size. A turned node's rect is the bounds of its box turned, so its
    /// ``PenRect/unturnedSize`` takes the override and its bounds grow to that size turned,
    /// from the same corner — as an unturned node grows from its own.
    ///
    /// - Parameters:
    ///   - rect: The settled rect.
    ///   - node: The node, for its rotation.
    ///   - overrides: The node's animation overrides.
    /// - Returns: The rect to draw the node in.
    static func overridden(_ rect: PenRect, of node: PenNode, by overrides: NodeOverrides?) -> PenRect {
        guard let overrides else { return rect }
        let x = overrides.x ?? rect.x
        let y = overrides.y ?? rect.y
        guard overrides.width != nil || overrides.height != nil else {
            return PenRect(x: x, y: y, width: rect.width, height: rect.height, unturnedSize: rect.unturnedSize)
        }
        guard let unturned = rect.unturnedSize else {
            return PenRect(x: x, y: y, width: overrides.width ?? rect.width, height: overrides.height ?? rect.height)
        }
        let size = PenSize(width: overrides.width ?? unturned.width, height: overrides.height ?? unturned.height)
        let bounds = PenLayoutEngine.rotatedBoundingBox(
            width: size.width, height: size.height, rotationDegrees: node.common.rotation?.literalValue ?? 0
        )
        return PenRect(x: x, y: y, width: bounds.width, height: bounds.height, unturnedSize: size)
    }

    /// Applies rotation/flip transform for a node. Isolated into its own function
    /// so that the temporary `overriddenNode` copy (1.2 KB) only lives on the
    /// stack for the duration of this call, not the caller's frame.
    private static func applyTransform(
        ref: NodeRef,
        drawRect: PenRect,
        rotationOverride: Double?,
        in context: CGContext
    ) {
        if let rotationOverride {
            var overriddenNode = ref.node
            overriddenNode.common.rotation = .literal(rotationOverride)
            let transform = PenTransformBuilder.buildTransform(for: overriddenNode, rect: drawRect)
            if !transform.isIdentity {
                context.concatenate(transform)
            }
        } else {
            let transform = PenTransformBuilder.buildTransform(for: ref.node, rect: drawRect)
            if !transform.isIdentity {
                context.concatenate(transform)
            }
        }
    }
}
