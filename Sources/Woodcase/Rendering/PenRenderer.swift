import CoreGraphics

/// Renders a `PenDocument` into a `CGImage` or onto a `CGContext`.
///
/// The renderer walks the document's node tree, drawing shapes, fills, strokes,
/// and children in the correct order. It uses layout rects computed by `PenLayoutEngine`
/// to position each node.
///
/// ## Pipeline Position
///
/// ```
/// Parse → Resolve → Expand → Layout → **Render**
/// ```
///
/// ## Usage
///
/// ```swift
/// let image = PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 800, height: 600))
/// ```
public enum PenRenderer {
    /// A function that provides images for image fills.
    /// The renderer calls this with the URL from the .pen file.
    /// Return `nil` to skip the image fill.
    public typealias ImageProvider = (String) -> CGImage?

    /// Renders a document into a new `CGImage`.
    ///
    /// - Parameters:
    ///   - document: The parsed and resolved document.
    ///   - layoutRects: Layout rectangles for each node, keyed by node ID.
    ///   - size: The output image size in points.
    ///   - scale: The scale factor (e.g. 2 for @2x). Defaults to 1.
    ///   - colorSpace: The color space for the output. Defaults to sRGB.
    ///   - rootNodeID: If provided, render only this node and its children — and every
    ///     top-level connection whose two anchors fall inside the image, drawn over them.
    ///   - overrides: Per-node property overrides for animation.
    ///   - imageProvider: Callback to load images for image fills.
    ///   - postIt: The words and identity colors notes, prompts and contexts are drawn with.
    ///     Defaults to English and each identity's ``ActorColor``.
    /// - Returns: A rendered `CGImage`, or `nil` if context creation fails.
    public static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        size: CGSize,
        scale: CGFloat = 1,
        colorSpace: CGColorSpace? = nil,
        rootNodeID: String? = nil,
        overrides: [String: NodeOverrides] = [:],
        imageProvider: ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) -> CGImage? {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)
        let bytesPerRow = pixelWidth * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Apply scale
        if scale != 1 {
            context.scaleBy(x: scale, y: scale)
        }

        // Flip coordinate system: CG is bottom-left origin, .pen is top-left
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        if let rootNodeID {
            // Subtree rendering: find the target node, translate to origin, render only that node
            guard let targetNode = findNode(id: rootNodeID, in: document.children) else {
                return context.makeImage()
            }
            if let rootRect = layoutRects[rootNodeID] {
                context.translateBy(x: CGFloat(-rootRect.x), y: CGFloat(-rootRect.y))
            }
            renderNodesIteratively([targetNode], layoutRects: layoutRects, in: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt)
            PenConnectionRenderer.renderConnections(
                over: rootNodeID, in: document, layoutRects: layoutRects, into: context,
                overrides: overrides, imageProvider: imageProvider
            )
        } else {
            render(document, layoutRects: layoutRects, into: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt)
        }

        return context.makeImage()
    }

    /// Renders a document into an existing `CGContext`.
    ///
    /// The context should already have its coordinate system set up (typically
    /// flipped so that (0,0) is top-left).
    ///
    /// With a `rootNodeID`, the node is drawn at its layout rect, in its parent's
    /// coordinates, and every top-level connection whose two anchors fall inside the
    /// context's clip bounds is drawn over it.
    ///
    /// - Parameter postIt: The words and identity colors notes, prompts and contexts are
    ///   drawn with.
    public static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        into context: CGContext,
        rootNodeID: String? = nil,
        overrides: [String: NodeOverrides] = [:],
        imageProvider: ImageProvider = { _ in nil },
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) {
        if let rootNodeID {
            // Subtree rendering: find target node, render only that node
            // No coordinate translation — caller manages positioning
            guard let targetNode = findNode(id: rootNodeID, in: document.children) else { return }
            renderNodesIteratively([targetNode], layoutRects: layoutRects, in: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt)
            PenConnectionRenderer.renderConnections(
                over: rootNodeID, in: document, layoutRects: layoutRects, into: context,
                overrides: overrides, imageProvider: imageProvider
            )
        } else {
            renderNodesIteratively(
                document.children, layoutRects: layoutRects,
                canvasRects: PenConnectionRenderer.canvasRects(for: document, layoutRects: layoutRects),
                in: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt
            )
        }
    }

    // MARK: - Node Lookup

    /// Searches the node tree for a node with the given ID.
    private static func findNode(id: String, in nodes: [PenNode]) -> PenNode? {
        for node in nodes {
            if node.id == id { return node }
            switch node.kind {
            case let .frame(data):
                if let children = data.children,
                   let found = findNode(id: id, in: children)
                {
                    return found
                }
            case let .group(data):
                if let children = data.children,
                   let found = findNode(id: id, in: children)
                {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Iterative Rendering

    /// Heap-allocated box to avoid copying large PenNode structs (1.2 KB each)
    /// onto the thread stack via the WorkItem enum.
    final class NodeRef {
        let node: PenNode
        init(_ node: PenNode) {
            self.node = node
        }
    }

    /// Work items for the iterative rendering loop, replacing recursive calls.
    /// PenNode values are boxed in NodeRef to keep WorkItem small—without this,
    /// each WorkItem would be >1.2 KB and exhaust cooperative-thread stacks.
    private enum WorkItem {
        /// Render a node: apply setup, draw own content, push children + cleanup.
        case renderNode(NodeRef)
        /// Restore a saved graphics state (for node exit or clip exit).
        case restoreGState
        /// Close the group layer a node opened for its opacity or blend mode.
        case endComposite(NodeComposite)
        /// Draw a group's inner shadows, inside its silhouette and over its children.
        case groupInnerShadows(NodeRef, [PenEffect.PenShadowEffect], PenRect)
    }

    /// Renders nodes iteratively using an explicit heap-allocated work stack,
    /// avoiding stack overflow on deeply nested documents.
    ///
    /// ## Why iterative?
    ///
    /// The previous recursive approach (`renderNode` → `renderFrame` → `renderNode`)
    /// added a large stack frame per tree level. Each frame carried CG state, effect
    /// arrays, closures, and — critically — copies of `PenNode` (1.2 KB due to the
    /// size of `PenNode.Kind`). On complex documents this exceeded the 512 KB
    /// cooperative-thread stack, crashing with SIGBUS.
    ///
    /// The iterative loop keeps call depth constant (O(1) stack frames regardless of
    /// tree depth). Node references are heap-boxed in ``NodeRef`` so the `WorkItem`
    /// enum and `processNode` stack frame stay small.
    ///
    /// ## Stack size caveat
    ///
    /// Even with boxing, debug-mode `switch` over `ref.node.kind` materializes a
    /// ~1 KB temporary per access. This limits cooperative-thread depth to ~150 in
    /// debug builds. Production callers (CLI main thread, app dispatch queues) have
    /// 8 MB+ stacks and are unaffected. Regression tests run on the main actor for this
    /// reason.
    static func renderNodesIteratively(
        _ nodes: [PenNode],
        layoutRects: [String: PenRect],
        canvasRects: [String: PenRect] = [:],
        in context: CGContext,
        overrides: [String: NodeOverrides],
        imageProvider: ImageProvider,
        postIt: PenPostIt.DrawingOptions = PenPostIt.DrawingOptions()
    ) {
        var stack: [WorkItem] = nodes.reversed().map { .renderNode(NodeRef($0)) }

        while let item = stack.popLast() {
            switch item {
            case let .renderNode(ref):
                processNode(
                    ref, stack: &stack,
                    layoutRects: layoutRects, canvasRects: canvasRects, in: context,
                    overrides: overrides, imageProvider: imageProvider, postIt: postIt
                )
            case .restoreGState:
                context.restoreGState()
            case let .endComposite(composite):
                endComposite(composite, in: context)
            case let .groupInnerShadows(ref, shadows, drawRect):
                guard case let .group(data) = ref.node.kind, let children = data.children else { continue }
                renderGroupInnerShadows(shadows, bounds: drawRect.cgRect, in: context) { target in
                    drawDescendantSilhouettes(
                        of: children, clip: nil, layoutRects: layoutRects, overrides: overrides,
                        imageProvider: imageProvider, in: target
                    )
                }
            }
        }
    }

    /// Processes a single node: performs setup inline, renders leaf content, and
    /// pushes children + cleanup work items onto the stack for container nodes.
    ///
    /// All access to the node goes through `ref.node` (a heap-allocated reference)
    /// to avoid copying PenNode (1.2 KB) onto the thread stack.
    private static func processNode(
        _ ref: NodeRef,
        stack: inout [WorkItem],
        layoutRects: [String: PenRect],
        canvasRects: [String: PenRect],
        in context: CGContext,
        overrides: [String: NodeOverrides],
        imageProvider: ImageProvider,
        postIt: PenPostIt.DrawingOptions
    ) {
        let nodeOverrides = overrides[ref.node.id]
        guard isEnabled(ref.node, overrides: nodeOverrides) else { return }

        // Skip non-visual node types; a connection has no box, and is drawn from where
        // its endpoints are.
        switch ref.node.kind {
        case .note, .prompt, .context:
            renderPostIt(ref, layoutRects: layoutRects, overrides: nodeOverrides, in: context, options: postIt)
            return
        case .ref, .unknown:
            return
        case let .connection(data):
            PenConnectionRenderer.render(
                ref.node, data: data, opacity: nodeOverrides?.opacity ?? ref.node.common.opacity?.literalValue,
                canvasRects: canvasRects, in: context, imageProvider: imageProvider
            )
            return
        default:
            break
        }

        // Saves the graphics state; the `.restoreGState` pushed below undoes it.
        guard let drawRect = enter(ref, layoutRects: layoutRects, overrides: nodeOverrides, in: context) else { return }

        // Collect effects
        let nodeEffects = effects(for: ref.node)
        let (outerShadows, innerShadows) = PenCastShadow.casts(of: ref.node)
        let blurEffect = nodeEffects?.all.compactMap { effect -> PenEffect.PenBlurEffect? in
            guard case let .blur(blur) = effect,
                  blur.enabled?.literalValue != false
            else { return nil }
            return blur
        }.first
        let backgroundBlurEffect = nodeEffects?.all.compactMap { effect -> PenEffect.PenBackgroundBlurEffect? in
            guard case let .backgroundBlur(bgBlur) = effect,
                  bgBlur.enabled?.literalValue != false
            else { return nil }
            return bgBlur
        }.first

        // Background blur: capture and blur the backdrop before the node's group layer opens
        // (a per-pixel layer clears what lies beneath), then draw it inside the layer so it
        // takes part in the node's compositing, before foreground blur and own content.
        let overrideFills = nodeOverrides?.fills
        let backgroundBlur = backgroundBlurEffect.flatMap { bgBlur -> (PenEffectRenderer.BlurredBackdrop, CGPath)? in
            guard let clipPath = PenShapeBuilder.buildPath(for: ref.node, rect: drawRect),
                  let backdrop = PenEffectRenderer.blurredBackdrop(
                      bgBlur, fills: overrideFills ?? fills(for: ref.node), clipPath: clipPath, in: context
                  )
            else { return nil }
            return (backdrop, clipPath)
        }

        // Opacity (an override wins) and blend mode make the node one isolated group.
        let effectiveOpacity = nodeOverrides?.opacity ?? ref.node.common.opacity?.literalValue
        let composite = beginComposite(for: ref.node, opacity: effectiveOpacity, in: context)

        if let (backdrop, clipPath) = backgroundBlur {
            PenEffectRenderer.drawBlurredBackdrop(backdrop, clipPath: clipPath, in: context)
        }

        // Extract children for container nodes
        let children: [PenNode]? = switch ref.node.kind {
        case let .frame(data):
            data.children
        case let .group(data):
            data.children
        default:
            nil
        }

        // A frame's or a group's shadows are cast by its descendants with its own paint.
        let clip = silhouetteClip(of: ref.node, drawRect: drawRect)
        func castDescendants(_ target: CGContext) {
            guard let children, !children.isEmpty else { return }
            drawDescendantSilhouettes(
                of: children, clip: clip, layoutRects: layoutRects, overrides: overrides,
                imageProvider: imageProvider, in: target
            )
        }
        let descendantBounds = outerShadows.isEmpty ? nil : children.flatMap {
            descendantSilhouetteBounds(of: $0, clipsTo: clip.map { _ in drawRect.cgRect }, layoutRects: layoutRects)
        }
        let own = OwnContent(
            drawRect: drawRect, outerShadows: outerShadows, innerShadows: innerShadows, overrideFills: overrideFills
        )

        // Blur path: render entire subtree into offscreen context
        if let blur = blurEffect {
            let shadowReach: CGFloat = outerShadows.map { cast -> CGFloat in
                let x: Double = abs(cast.shadow.offset?.x.literalValue ?? 0)
                let y: Double = abs(cast.shadow.offset?.y.literalValue ?? 0)
                return CGFloat(max(x, y) + (cast.shadow.blur?.literalValue ?? 0)) + max(cast.spread, 0)
            }.max() ?? 0
            PenEffectRenderer.renderBlur(blur, rect: drawRect, overflow: shadowReach, in: context) { offscreenCtx in
                renderOwnContent(
                    ref.node, own, descendants: castDescendants, descendantBounds: descendantBounds,
                    imageProvider: imageProvider, in: offscreenCtx
                )
                renderChildren(
                    ref, drawRect: drawRect, children: children,
                    layoutRects: layoutRects, in: offscreenCtx,
                    overrides: overrides, imageProvider: imageProvider, postIt: postIt
                )
                if case .group = ref.node.kind {
                    renderGroupInnerShadows(innerShadows.map(\.shadow), bounds: drawRect.cgRect, in: offscreenCtx, silhouette: castDescendants)
                }
            }
            // Cleanup: close the group layer + restore GState
            if let composite {
                endComposite(composite, in: context)
            }
            context.restoreGState()
            return
        }

        // Non-blur path: own content now, before the frame's clip, then children and
        // cleanup through the stack. Pushed in reverse execution order (the stack is LIFO):
        // restoreGState — pushed first, executed last.
        renderOwnContent(
            ref.node, own, descendants: castDescendants, descendantBounds: descendantBounds,
            imageProvider: imageProvider, in: context
        )
        stack.append(.restoreGState)
        if let composite {
            stack.append(.endComposite(composite))
        }

        // Push children + clip cleanup for container nodes
        if let children, !children.isEmpty {
            switch ref.node.kind {
            case let .frame(data):
                guard let path = PenShapeBuilder.buildPath(for: ref.node, rect: drawRect) else { break }
                let shouldClip = data.clip?.literalValue == true
                if shouldClip {
                    // restoreGState for clip will execute after all children
                    stack.append(.restoreGState)
                }
                for child in children.reversed() {
                    stack.append(.renderNode(NodeRef(child)))
                }
                // Clip setup executes now, before children
                if shouldClip {
                    context.saveGState()
                    context.addPath(path)
                    context.clip()
                }
            case .group:
                // A group's inner shadow falls over its children, so it runs after them.
                if !innerShadows.isEmpty {
                    stack.append(.groupInnerShadows(ref, innerShadows.map(\.shadow), drawRect))
                }
                for child in children.reversed() {
                    stack.append(.renderNode(NodeRef(child)))
                }
            default:
                break
            }
        }
    }

    /// Renders a container's children iteratively into a context, inside the frame's clip.
    /// Used for the blur path, where the entire subtree must render into an offscreen context.
    private static func renderChildren(
        _ ref: NodeRef,
        drawRect: PenRect,
        children: [PenNode]?,
        layoutRects: [String: PenRect],
        in context: CGContext,
        overrides: [String: NodeOverrides],
        imageProvider: ImageProvider,
        postIt: PenPostIt.DrawingOptions
    ) {
        guard let children, !children.isEmpty else { return }
        switch ref.node.kind {
        case let .frame(data):
            guard let path = PenShapeBuilder.buildPath(for: ref.node, rect: drawRect) else { break }
            let shouldClip = data.clip?.literalValue == true
            if shouldClip {
                context.saveGState()
                context.addPath(path)
                context.clip()
            }
            renderNodesIteratively(
                children, layoutRects: layoutRects,
                in: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt
            )
            if shouldClip {
                context.restoreGState()
            }
        case .group:
            renderNodesIteratively(
                children, layoutRects: layoutRects,
                in: context, overrides: overrides, imageProvider: imageProvider, postIt: postIt
            )
        default:
            break
        }
    }
}
