//
//  ReactEmitter+Effects.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Effects on a CSS box

    /// The stroke and effect declarations of a node drawn as a CSS box — a frame, a
    /// rectangle, a CSS ellipse or a browser — with every inset and outer shadow in one
    /// `box-shadow` list.
    ///
    /// Pen draws a node's outer shadows, then its fills, then its inner shadows, then its
    /// stroke. CSS paints outer box-shadows under the background and inset ones over it,
    /// and within a list the first entry on top, so the list is the stroke's shadows (an
    /// inset one, a spread one for a centered or outer stroke — ``emitStroke(_:)``), then the
    /// inner shadows top first, then the outer shadows top first, each spread by the
    /// stroke's reach past the box (``shadowSpread(_:)``).
    ///
    /// - Parameters:
    ///   - stroke: The node's stroke, if it has one.
    ///   - effects: The node's effects, if it has any.
    ///   - showsBackdrop: Whether the node has a visible fill: Pen draws no background
    ///     blur through a node without one (``PenFills/hasVisiblePaint``).
    ///   - layered: Whether the outer shadows are drawn by layers of their own
    ///     (``shadowLayerStyles(_:borderRadius:stroke:)``) and left out of the list.
    /// - Returns: The declarations.
    static func emitStrokeAndEffects(
        stroke: (any PenStrokable)?,
        effects: PenEffects?,
        showsBackdrop: Bool,
        layered: Bool = false
    ) -> [(String, String)] {
        let strokeStyles = stroke.map { emitStroke($0) } ?? []
        let drawn = NodeEffects(effects)

        var shadows: [String] = []
        if let strokeShadow = strokeStyles.first(where: { $0.0 == "boxShadow" })?.1 {
            shadows.append(String(strokeShadow.dropFirst().dropLast()))
        }
        shadows += drawn.innerShadowList
        if !layered {
            shadows += drawn.outerShadowList(spread: shadowSpread(stroke))
        }

        var result: [(String, String)] = []
        if !shadows.isEmpty {
            result.append(("boxShadow", "\"\(shadows.joined(separator: ", "))\""))
        }
        result.append(contentsOf: strokeStyles.filter { $0.0 != "boxShadow" })
        if let blur = drawn.blurFunction {
            result.append(("filter", "\"\(blur)\""))
        }
        if showsBackdrop, let backdrop = drawn.backdropFunction {
            result.append(("backdropFilter", "\"\(backdrop)\""))
            result.append(("WebkitBackdropFilter", "\"\(backdrop)\""))
        }
        return result
    }

    /// The styles of the layers that draw a CSS box's outer shadows when one of them is
    /// blended, one layer per shadow in Pen's order, or `nil` when the box's own
    /// `box-shadow` can draw them.
    ///
    /// CSS blends an element, not one entry of its shadow list, so a blended shadow needs
    /// an element of its own: an absolutely positioned `<div aria-hidden="true">` over the
    /// box, with the box's corner radii, casting that one shadow with its
    /// `mix-blend-mode`. All the outer shadows move to layers together, so they keep
    /// their order — a later layer paints over an earlier one. The host must be
    /// positioned. Being positioned, a layer paints over later siblings that are not,
    /// where Pen draws those over the shadow.
    ///
    /// - Parameters:
    ///   - effects: The node's effects.
    ///   - borderRadius: The box's `borderRadius` value, if it has one.
    ///   - stroke: The node's stroke, whose reach past the box spreads each shadow
    ///     (``shadowSpread(_:)``).
    /// - Returns: One style list per outer shadow, bottom first, or `nil`.
    static func shadowLayerStyles(
        _ effects: PenEffects?, borderRadius: String?, stroke: (any PenStrokable)?
    ) -> [[(String, String)]]? {
        let drawn = NodeEffects(effects)
        guard drawn.outerShadows.contains(where: \.isBlended) else { return nil }
        return drawn.outerShadows.map { shadow in
            var styles = [("position", "\"absolute\""), ("inset", "0")]
            if let borderRadius {
                styles.append(("borderRadius", borderRadius))
            }
            styles.append(("boxShadow", "\"\(shadow.cssShadow(spread: shadowSpread(stroke)))\""))
            if let mode = shadow.blendMode, shadow.isBlended {
                styles.append(("mixBlendMode", "\"\(blendModeToCSSValue(mode))\""))
            }
            styles.append(("pointerEvents", "\"none\""))
            return styles
        }
    }

    /// Writes a childless box's `<div>` holding its shadow layers, then its stroke overlay,
    /// or hands it to ``emitBoxElement(_:overlay:indent:ctx:)`` when it has no layers.
    static func emitBoxElement(
        _ styles: [(String, String)],
        shadowLayers: [[(String, String)]]?,
        overlay: [(String, String)]?,
        indent: Int,
        ctx: EmitContext
    ) {
        guard let shadowLayers else {
            emitBoxElement(styles, overlay: overlay, indent: indent, ctx: ctx)
            return
        }
        let pad = String(repeating: " ", count: indent)
        ctx.lines.append("\(pad)<div")
        ctx.lines.append("\(pad)  style={{")
        for (key, value) in styles {
            ctx.lines.append("\(pad)    \(key): \(value),")
        }
        ctx.lines.append("\(pad)  }}")
        ctx.lines.append("\(pad)>")
        emitShadowLayers(shadowLayers, indent: indent + 2, ctx: ctx)
        if let overlay {
            emitStrokeOverlay(overlay, indent: indent + 2, ctx: ctx)
        }
        ctx.lines.append("\(pad)</div>")
    }

    /// Writes each shadow layer as a hidden `<div>`, bottom first.
    static func emitShadowLayers(_ layers: [[(String, String)]], indent: Int, ctx: EmitContext) {
        for layer in layers {
            emitStrokeOverlay(layer, indent: indent, ctx: ctx)
        }
    }

    // MARK: - Effects on glyphs, SVG shapes and groups

    /// The effect declarations of a text node: its outer shadows cast by its glyphs
    /// (`text-shadow`, top first) and its layer blur (`filter`).
    ///
    /// Painted text — shown through `background-clip: text` — casts its shadows through
    /// `drop-shadow()` filters instead: a `text-shadow` is painted over the element's
    /// background, so it would cover the clipped paint. Inner shadows and background blur
    /// are not written: CSS has no inner text shadow, and a backdrop filter would blur the
    /// text's whole box rather than behind its glyphs.
    ///
    /// - Parameters:
    ///   - effects: The node's effects.
    ///   - painted: Whether the text's fill is drawn through its glyphs as a background.
    /// - Returns: The declarations.
    static func textEffectStyles(_ effects: PenEffects?, painted: Bool) -> [(String, String)] {
        let drawn = NodeEffects(effects)
        if painted {
            return filterStyles(drawn)
        }
        var styles: [(String, String)] = []
        if !drawn.outerShadows.isEmpty {
            styles.append(("textShadow", "\"\(drawn.outerShadowList.joined(separator: ", "))\""))
        }
        if let blur = drawn.blurFunction {
            styles.append(("filter", "\"\(blur)\""))
        }
        return styles
    }

    /// The effect declarations of a node whose outline CSS cannot shadow as a box — an
    /// icon, a shape drawn as SVG, a group: one `filter` whose `drop-shadow()`s cast the
    /// outer shadows from what the element paints, then the layer blur over them all, as
    /// Pen blurs a node's shadows with it.
    ///
    /// A `drop-shadow` is cast by the painted pixels at their own alpha: a translucent
    /// part casts a fainter shadow than Pen's opaque silhouette, the shadow shows through
    /// it, and on a group every child's own shadow is cast again — an approximation of
    /// Pen's silhouette (<doc:PenRendering>, *Effects*).
    ///
    /// - Parameters:
    ///   - effects: The node's effects.
    ///   - leading: Filter functions applied first — an icon's inner shadows
    ///     (``iconInnerShadowFilters(_:size:nodeID:)``), which Pen draws over the glyph and
    ///     under nothing its outer shadows cast.
    /// - Returns: The declarations.
    static func filterEffectStyles(_ effects: PenEffects?, leading: [String] = []) -> [(String, String)] {
        filterStyles(NodeEffects(effects), leading: leading)
    }

    /// One `filter` of the `leading` functions, then drop-shadows, then blur, or nothing.
    private static func filterStyles(_ drawn: NodeEffects, leading: [String] = []) -> [(String, String)] {
        let functions = leading + drawn.dropShadowFunctions + [drawn.blurFunction].compactMap(\.self)
        guard !functions.isEmpty else { return [] }
        return [("filter", "\"\(functions.joined(separator: " "))\"")]
    }

    /// Warns once for a node whose blended shadows are drawn unblended: CSS blends an
    /// element, not one of its shadows, and only a box's outer shadows get layers of their
    /// own (``shadowLayerStyles(_:borderRadius:stroke:)``, where ``layersShadows(_:)``).
    /// Inner shadows count only where they are `inset` box-shadows: an SVG filter blends
    /// them, and a node whose inner shadows are left out is warned about them once already
    /// (``warnDroppedInnerShadows(_:ctx:)``), so each shadow is named at most once.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - ctx: The emission context whose diagnostics take the warning.
    static func warnUnblendedShadows(_ node: PenNode, ctx: EmitContext) {
        let drawn = NodeEffects(PenRenderer.effects(for: node))
        let unblendedInner = innerShadowRoute(node) == .insetBoxShadow ? drawn.innerShadows : []
        let unblended = (layersShadows(node) ? [] : drawn.outerShadows) + unblendedInner
        guard unblended.contains(where: \.isBlended), ctx.unblendedShadowWarnedNodes.insert(node.id).inserted else { return }
        ctx.diagnostics?.warn(unblendedShadowWarning, stage: .codeGen, nodeID: node.id)
    }

    /// Whether a node's outer shadows can be drawn by layers of their own: a CSS box that
    /// holds children and does not clip them — a rectangle, an ellipse drawn as a CSS box
    /// (no inner radius, a full sweep, as ``emitEllipse(_:data:indent:ctx:isRoot:parentLayout:)``
    /// decides) or a frame without `clip`, whose `overflow: hidden` would cut the shadow.
    static func layersShadows(_ node: PenNode) -> Bool {
        switch node.kind {
        case .rectangle:
            true
        case let .ellipse(data):
            drawsAsBox(data)
        case let .frame(data):
            data.clip?.literalValue != true
        default:
            false
        }
    }

    /// The warning for a shadow whose blend mode React does not draw.
    static let unblendedShadowWarning = "React draws this node's blended shadow without its blend mode"
}
