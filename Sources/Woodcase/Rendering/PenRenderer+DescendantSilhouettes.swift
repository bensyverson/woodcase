import CoreGraphics

extension PenRenderer {
    /// Draws a frame's or a group's descendants in opaque ink: the part of its silhouette its
    /// children cast, under its outer shadows and, for a group, inside its inner shadows.
    ///
    /// Pen CLI 0.3.13 casts a container's shadow from its rendered content
    /// (`render-content-shadows.pen`, `render-group-shadows.pen`): each descendant is drawn as
    /// ``PenShadowSilhouette`` draws it for its own shadow, so a translucent fill or a child
    /// at half opacity casts at full strength, a disabled or transparent fill casts nothing,
    /// and a line casts its stroke. A frame's children cast through it, clipped to it when it
    /// clips, and a group's through it; a child's own shadow casts nothing.
    ///
    /// Walks an explicit stack, as the renderer does, so a deep tree cannot overflow a task's
    /// thread stack; only a clipping frame inside another costs a level of recursion. A
    /// clipping frame's descendants are drawn through ``PenSilhouetteMask``, cut to its
    /// outline there, since an outer shadow draws its silhouette outside the context's clip.
    ///
    /// - Parameters:
    ///   - children: The container's children.
    ///   - clip: The container's outline when it is a frame that clips its children, else `nil`.
    ///   - layoutRects: Layout rects, keyed by node ID, relative to the parent.
    ///   - overrides: Per-node animation overrides.
    ///   - imageProvider: Resolves image paints for text and icons.
    ///   - context: The context to draw into, in the container's own space.
    static func drawDescendantSilhouettes(
        of children: [PenNode],
        clip: CGPath?,
        layoutRects: [String: PenRect],
        overrides: [String: NodeOverrides],
        imageProvider: ImageProvider,
        in context: CGContext
    ) {
        guard let clip else {
            walkSilhouettes(
                of: children, layoutRects: layoutRects, overrides: overrides, imageProvider: imageProvider, in: context
            )
            return
        }
        PenSilhouetteMask.draw(within: clip.boundingBoxOfPath, clip: clip, in: context) { target in
            walkSilhouettes(
                of: children, layoutRects: layoutRects, overrides: overrides, imageProvider: imageProvider, in: target
            )
        }
    }

    /// Draws `children`'s silhouettes and their descendants', unclipped at this level.
    private static func walkSilhouettes(
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
            guard isEnabled(ref.node, overrides: nodeOverrides), castsIntoContainer(ref.node),
                  let drawRect = enter(ref, layoutRects: layoutRects, overrides: nodeOverrides, in: context)
            else { continue }
            stack.append(.restoreGState)
            PenShadowSilhouette.draw(
                ref.node, rect: drawRect, spread: 0, in: context, children: { _ in }, imageProvider: imageProvider
            )
            let grandchildren: [PenNode]
            switch ref.node.kind {
            case let .group(data):
                grandchildren = data.children ?? []
            case let .frame(data):
                grandchildren = data.children ?? []
                if !grandchildren.isEmpty, let outline = silhouetteClip(of: ref.node, drawRect: drawRect) {
                    drawDescendantSilhouettes(
                        of: grandchildren, clip: outline, layoutRects: layoutRects, overrides: overrides,
                        imageProvider: imageProvider, in: context
                    )
                    continue
                }
            default:
                grandchildren = []
            }
            for child in grandchildren.reversed() {
                stack.append(.draw(NodeRef(child)))
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

    /// The bounds of everything a container's children may cast into its silhouette, in its
    /// own space: their painted extents (``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``),
    /// cut to the container's draw rect when it clips — or `nil` when it has no child.
    ///
    /// - Parameters:
    ///   - children: The container's children.
    ///   - clipsTo: The container's draw rect when it is a frame that clips, else `nil`.
    ///   - layoutRects: Layout rects, keyed by node ID, relative to the parent.
    static func descendantSilhouetteBounds(
        of children: [PenNode], clipsTo: CGRect?, layoutRects: [String: PenRect]
    ) -> CGRect? {
        let extents = children.compactMap { child -> CGRect? in
            guard let rect = layoutRects[child.id] else { return nil }
            return PenLayoutEngine.paintedExtent(of: child, rect: rect, layoutRects: layoutRects).cgRect
        }
        guard let first = extents.first else { return nil }
        let union = extents.dropFirst().reduce(first) { $0.union($1) }
        return clipsTo.map { union.intersection($0) } ?? union
    }

    /// The outline a node's descendants' silhouettes are clipped to: a frame's own, when it
    /// clips its children; `nil` for any other node.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - drawRect: Its draw rect, in its own space.
    static func silhouetteClip(of node: PenNode, drawRect: PenRect) -> CGPath? {
        guard case let .frame(data) = node.kind, data.clip?.literalValue == true else { return nil }
        return PenShapeBuilder.buildPath(for: node, rect: drawRect)
    }

    /// One step of ``drawDescendantSilhouettes(of:clip:layoutRects:overrides:imageProvider:in:)``'s walk.
    private enum SilhouetteStep {
        /// Draw a descendant's silhouette, then walk into its children.
        case draw(NodeRef)
        /// Leave a descendant's space.
        case restoreGState
    }

    /// Whether a descendant contributes to its container's silhouette: the kinds with no box
    /// of their own, and a post-it, do not.
    private static func castsIntoContainer(_ node: PenNode) -> Bool {
        switch node.kind {
        case .note, .prompt, .context, .ref, .unknown, .connection: false
        default: true
        }
    }
}
