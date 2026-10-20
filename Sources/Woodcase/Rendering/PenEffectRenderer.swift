import CoreGraphics

/// Renders visual effects — outer and inner shadows here, layer blur and background blur in
/// its extensions — on nodes.
///
/// A shadow's `blur` is twice its Gaussian's sigma, which is also what CoreGraphics' own
/// shadow blur means, so it passes straight through, scaled to device pixels.
enum PenEffectRenderer {
    /// The shadow color Pen draws when a shadow names none: black at half alpha.
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
    /// A shadow's spread grows the silhouette it is cast by (step 1) but not the one erased
    /// (step 2), so a spread shadow never shows under the node either.
    ///
    /// - Parameters:
    ///   - shadows: The node's outer shadows and their spreads; disabled ones draw nothing.
    ///   - bounds: A rectangle containing the silhouette, grown by any spread, in the
    ///     context's current space.
    ///   - context: The context to draw into.
    ///   - silhouette: Draws the node's silhouette in opaque ink into the context it is
    ///     given, grown by the spread it is given.
    static func renderOuterShadows(
        _ shadows: [PenCastShadow],
        bounds: CGRect,
        in context: CGContext,
        silhouette: (CGContext, CGFloat) -> Void
    ) {
        let enabled = shadows.filter { $0.shadow.enabled?.literalValue != false }
        guard !enabled.isEmpty else { return }
        let scale = deviceScale(of: context)
        let clipBox = context.boundingBoxOfClipPath
        for entry in enabled {
            let shadow = entry.shadow
            let blur = CGFloat(shadow.blur?.literalValue ?? 0)
            // Far enough right that the silhouette, and none of its own pixels, is drawn
            // inside the clip.
            let shift = abs(clipBox.maxX - bounds.minX) + clipBox.width + bounds.width + 4 * blur + 64
            let travel = CGSize(width: shift, height: 0).applying(context.ctm)
            let cast = offset(of: shadow, in: context)

            PenBlendLayer.draw(shadow.blendMode, in: context) {
                context.saveGState()
                context.beginTransparencyLayer(auxiliaryInfo: nil)

                context.saveGState()
                context.setShadow(
                    offset: CGSize(width: cast.width - travel.width, height: cast.height - travel.height),
                    blur: blur * scale,
                    color: color(of: shadow)
                )
                context.translateBy(x: shift, y: 0)
                silhouette(context, entry.spread)
                context.restoreGState()

                context.setBlendMode(.destinationOut)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                silhouette(context, 0)
                context.endTransparencyLayer()

                context.endTransparencyLayer()
                context.restoreGState()
            }
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
    /// the shadow into the ring (`render-inner-shadow-shapes`, `donut`). A `spread` shrinks
    /// the cut-out shape, so the shadow reaches further in — CSS's inset spread.
    static func renderInnerShadow(
        _ shadow: PenEffect.PenShadowEffect,
        path: CGPath,
        fillRule: CGPathFillRule = .winding,
        spread: CGFloat = 0,
        in context: CGContext
    ) {
        guard shadow.enabled?.literalValue != false else { return }

        let blur = CGFloat(shadow.blur?.literalValue ?? 0)
        let pointOffset = pointOffset(of: shadow)
        let margin = blur + max(abs(pointOffset.width), abs(pointOffset.height)) + 100
        let outerRect = path.boundingBox.insetBy(dx: -margin, dy: -margin)
        let scale = deviceScale(of: context)

        PenBlendLayer.draw(shadow.blendMode, in: context) {
            context.saveGState()
            context.addPath(path)
            context.clip(using: fillRule)
            context.setShadow(offset: offset(of: shadow, in: context), blur: blur * scale, color: color(of: shadow))

            let invertedPath = CGMutablePath()
            invertedPath.addRect(outerRect)
            invertedPath.addPath(PenShadowSilhouette.spread(path, rule: fillRule, by: -spread).path)
            context.addPath(invertedPath)
            context.setFillColor(PenShadowSilhouette.ink)
            context.fillPath(using: .evenOdd)

            context.restoreGState()
        }
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
        let pointOffset = pointOffset(of: shadow)
        let margin = 2 * blur + max(abs(pointOffset.width), abs(pointOffset.height)) + 100
        let outerRect = bounds.insetBy(dx: -margin, dy: -margin)
        let scale = deviceScale(of: context)

        PenBlendLayer.draw(shadow.blendMode, in: context) {
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)

            context.saveGState()
            context.setShadow(offset: offset(of: shadow, in: context), blur: blur * scale, color: color(of: shadow))
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
    }

    // MARK: - Shared

    /// The shadow's color, or ``defaultShadowColor`` when it names none that parses.
    private static func color(of shadow: PenEffect.PenShadowEffect) -> CGColor {
        shadow.color?.literalValue.flatMap { PenColorParser.parse($0) } ?? defaultShadowColor
    }

    /// The shadow's offset in the node's own space, in points, y down.
    private static func pointOffset(of shadow: PenEffect.PenShadowEffect) -> CGSize {
        CGSize(width: shadow.offset?.x.literalValue ?? 0, height: shadow.offset?.y.literalValue ?? 0)
    }

    /// The shadow's offset in CoreGraphics' shadow space — the context's base space, device
    /// pixels with y up in a bitmap — carried there through the CTM.
    ///
    /// CoreGraphics casts a shadow in base space, untouched by the CTM, but Pen turns and
    /// flips a node's shadows with it (a `0, 24` shadow on a node turned 90° falls on its
    /// right edge), its ancestors' turns included. So the offset goes through the CTM's
    /// linear part — its turn, flips and scale, and the renderer's own y-down flip — not
    /// just its scale.
    private static func offset(of shadow: PenEffect.PenShadowEffect, in context: CGContext) -> CGSize {
        pointOffset(of: shadow).applying(context.ctm)
    }
}
