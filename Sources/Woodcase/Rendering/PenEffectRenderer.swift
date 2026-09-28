import CoreGraphics

/// Renders visual effects — outer and inner shadows here, layer blur and background blur in
/// its extensions — on nodes.
///
/// A shadow's `blur` is twice its Gaussian's sigma, which is also what CoreGraphics' own
/// shadow blur means, so it passes straight through, scaled to device pixels.
enum PenEffectRenderer {
    /// The shadow colour Pen draws when a shadow names none: black at half alpha.
    static let defaultShadowColor = CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 0.5]
    )!

    /// Device pixels per point of the context's current space, whatever its rotation.
    static func deviceScale(of context: CGContext) -> CGFloat {
        let ctm = context.ctm
        return (ctm.a * ctm.a + ctm.b * ctm.b).squareRoot()
    }

    // MARK: - Outer Shadow

    /// Draws every enabled outer shadow of a node, in array order, before its content.
    ///
    /// Pen casts an outer shadow from the node's **silhouette** — its shape and stroke, drawn
    /// opaque whatever the paint's own alpha — and never lets it show through the node: a
    /// translucent fill shows what is behind the node, not the shadow. Each shadow is drawn
    /// into its own layer, composited with the shadow's `blendMode`:
    ///
    /// 1. The silhouette is drawn far outside the clip with a CoreGraphics shadow whose
    ///    offset brings the shadow back, so only the shadow lands.
    /// 2. The silhouette is erased from the layer (`destinationOut`), knocking the shadow out
    ///    from under the node.
    ///
    /// - Parameters:
    ///   - shadows: The node's outer shadows; disabled ones draw nothing.
    ///   - bounds: A rectangle containing the silhouette, in the context's current space.
    ///   - context: The context to draw into.
    ///   - silhouette: Draws the node's silhouette in opaque ink into the context it is given.
    static func renderOuterShadows(
        _ shadows: [PenEffect.PenShadowEffect],
        bounds: CGRect,
        in context: CGContext,
        silhouette: (CGContext) -> Void
    ) {
        let enabled = shadows.filter { $0.enabled?.literalValue != false }
        guard !enabled.isEmpty else { return }
        let scale = deviceScale(of: context)
        let clipBox = context.boundingBoxOfClipPath
        for shadow in enabled {
            let blur = CGFloat(shadow.blur?.literalValue ?? 0)
            // Far enough right that the silhouette, and none of its own pixels, is drawn
            // inside the clip.
            let shift = abs(clipBox.maxX - bounds.minX) + clipBox.width + bounds.width + 4 * blur + 64
            let travel = CGSize(width: shift, height: 0).applying(context.ctm)
            let cast = offset(of: shadow, scale: scale)

            context.saveGState()
            if let blendMode = shadow.blendMode {
                context.setBlendMode(blendMode.cgBlendMode)
            }
            context.beginTransparencyLayer(auxiliaryInfo: nil)

            context.saveGState()
            context.setShadow(
                offset: CGSize(width: cast.width - travel.width, height: cast.height - travel.height),
                blur: blur * scale,
                color: color(of: shadow)
            )
            context.translateBy(x: shift, y: 0)
            silhouette(context)
            context.restoreGState()

            context.setBlendMode(.destinationOut)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            silhouette(context)
            context.endTransparencyLayer()

            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    // MARK: - Inner Shadow

    /// Renders an inner shadow within the given shape path.
    ///
    /// Uses the inverted-path technique: clips to the shape, then fills a large rectangle
    /// with the shape cut out of it, casting a CoreGraphics shadow, so the shadow falls
    /// inward from the shape's edge. Pen paints inner shadows after a node's fills and
    /// before its stroke and children; the caller keeps that order.
    ///
    /// The clip takes the shape's own fill rule: a donut's hole is outside it, and casts
    /// the shadow into the ring (`render-inner-shadow-shapes`, `donut`).
    static func renderInnerShadow(
        _ shadow: PenEffect.PenShadowEffect,
        path: CGPath,
        fillRule: CGPathFillRule = .winding,
        in context: CGContext
    ) {
        guard shadow.enabled?.literalValue != false else { return }

        let blur = CGFloat(shadow.blur?.literalValue ?? 0)
        let pointOffset = offset(of: shadow, scale: 1)
        let margin = blur + max(abs(pointOffset.width), abs(pointOffset.height)) + 100
        let outerRect = path.boundingBox.insetBy(dx: -margin, dy: -margin)
        let scale = deviceScale(of: context)

        context.saveGState()
        if let blendMode = shadow.blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
        context.addPath(path)
        context.clip(using: fillRule)
        context.setShadow(offset: offset(of: shadow, scale: scale), blur: blur * scale, color: color(of: shadow))

        let invertedPath = CGMutablePath()
        invertedPath.addRect(outerRect)
        invertedPath.addPath(path)
        context.addPath(invertedPath)
        context.setFillColor(PenShadowSilhouette.ink)
        context.fillPath(using: .evenOdd)

        context.restoreGState()
    }

    /// Renders an inner shadow inside a silhouette that is drawn, not a path: a group's
    /// descendants' combined outline.
    ///
    /// The inverted silhouette — a rectangle wider than the shadow's reach, with the
    /// silhouette erased from it — is cast as one layer with a CoreGraphics shadow, and the
    /// result is then kept only where the silhouette covers (`destinationIn`), which also
    /// removes the inverted ink itself.
    ///
    /// - Parameters:
    ///   - shadow: The inner shadow; a disabled one draws nothing.
    ///   - bounds: A rectangle containing the silhouette, in the context's current space.
    ///   - context: The context to draw into.
    ///   - silhouette: Draws the silhouette in opaque ink into the context it is given.
    static func renderInnerShadow(
        _ shadow: PenEffect.PenShadowEffect,
        bounds: CGRect,
        in context: CGContext,
        silhouette: (CGContext) -> Void
    ) {
        guard shadow.enabled?.literalValue != false else { return }

        let blur = CGFloat(shadow.blur?.literalValue ?? 0)
        let pointOffset = offset(of: shadow, scale: 1)
        let margin = 2 * blur + max(abs(pointOffset.width), abs(pointOffset.height)) + 100
        let outerRect = bounds.insetBy(dx: -margin, dy: -margin)
        let scale = deviceScale(of: context)

        context.saveGState()
        if let blendMode = shadow.blendMode {
            context.setBlendMode(blendMode.cgBlendMode)
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        context.saveGState()
        context.setShadow(offset: offset(of: shadow, scale: scale), blur: blur * scale, color: color(of: shadow))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(PenShadowSilhouette.ink)
        context.fill(outerRect)
        context.setBlendMode(.destinationOut)
        silhouette(context)
        context.endTransparencyLayer()
        context.restoreGState()

        context.setBlendMode(.destinationIn)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        silhouette(context)
        context.endTransparencyLayer()

        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - Shared

    /// The shadow's colour, or ``defaultShadowColor`` when it names none that parses.
    private static func color(of shadow: PenEffect.PenShadowEffect) -> CGColor {
        shadow.color?.literalValue.flatMap { PenColorParser.parse($0) } ?? defaultShadowColor
    }

    /// The shadow's offset in CoreGraphics' shadow space: device pixels, y up.
    ///
    /// A shadow offset does not follow the CTM, so the point offset is scaled to pixels and
    /// its y negated for the renderer's y-down space.
    private static func offset(of shadow: PenEffect.PenShadowEffect, scale: CGFloat) -> CGSize {
        let x = CGFloat(shadow.offset?.x.literalValue ?? 0)
        let y = CGFloat(shadow.offset?.y.literalValue ?? 0)
        return CGSize(width: x * scale, height: -y * scale)
    }
}
