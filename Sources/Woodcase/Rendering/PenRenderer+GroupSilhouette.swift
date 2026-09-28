import CoreGraphics

extension PenRenderer {
    /// Draws a group's silhouette in opaque ink: the combined outline of its descendants,
    /// which casts the group's outer and inner shadows.
    ///
    /// Pen 1.2.14 reaches descendants through groups only (`render-group-shadows.pen`). Each
    /// one is drawn as ``PenShadowSilhouette`` draws it for its own shadow, so a translucent
    /// fill casts at full strength and a frame casts its box while its own children cast
    /// nothing. A line casts nothing, and neither does a child's opacity or its own shadow.
    ///
    /// Walks an explicit stack, as the renderer does, so a deep tree cannot overflow a task's
    /// thread stack.
    ///
    /// - Parameters:
    ///   - children: The group's children.
    ///   - layoutRects: Layout rects, keyed by node ID, relative to the parent.
    ///   - overrides: Per-node animation overrides.
    ///   - imageProvider: Resolves image paints for text and icons.
    ///   - context: The context to draw into, in the group's own space.
    static func drawGroupSilhouette(
        of children: [PenNode],
        layoutRects: [String: PenRect],
        overrides: [String: NodeOverrides],
        imageProvider: ImageProvider,
        in context: CGContext
    ) {
        var stack: [SilhouetteStep] = children.reversed().map { .draw(NodeRef($0)) }
        while let step = stack.popLast() {
            guard case let .draw(ref) = step else {
                context.restoreGState()
                continue
            }
            let nodeOverrides = overrides[ref.node.id]
            guard isEnabled(ref.node, overrides: nodeOverrides), castsIntoGroup(ref.node),
                  let drawRect = enter(ref, layoutRects: layoutRects, overrides: nodeOverrides, in: context)
            else { continue }
            stack.append(.restoreGState)
            if case let .group(data) = ref.node.kind {
                for child in (data.children ?? []).reversed() {
                    stack.append(.draw(NodeRef(child)))
                }
            } else {
                PenShadowSilhouette.draw(
                    ref.node, rect: drawRect, in: context, children: { _ in }, imageProvider: imageProvider
                )
            }
        }
    }

    /// Draws a group's inner shadows, in array order, inside its silhouette.
    ///
    /// Pen draws them over the group's children, which are the only content a group has.
    ///
    /// - Parameters:
    ///   - shadows: The group's enabled inner shadows.
    ///   - bounds: The group's draw rect, in its own space.
    ///   - context: The context to draw into, in the group's own space.
    ///   - silhouette: Draws the group's silhouette in opaque ink.
    static func renderGroupInnerShadows(
        _ shadows: [PenEffect.PenShadowEffect],
        bounds: CGRect,
        in context: CGContext,
        silhouette: (CGContext) -> Void
    ) {
        for shadow in shadows {
            PenEffectRenderer.renderInnerShadow(shadow, bounds: bounds, in: context, silhouette: silhouette)
        }
    }

    /// One step of ``drawGroupSilhouette(of:layoutRects:overrides:imageProvider:in:)``'s walk.
    private enum SilhouetteStep {
        /// Draw a descendant's silhouette, or walk into a nested group.
        case draw(NodeRef)
        /// Leave a descendant's space.
        case restoreGState
    }

    /// Whether a group's descendant contributes to the group's silhouette: a line and the
    /// kinds with no box of their own do not.
    private static func castsIntoGroup(_ node: PenNode) -> Bool {
        switch node.kind {
        case .line, .note, .prompt, .context, .ref, .unknown, .connection: false
        default: true
        }
    }
}
