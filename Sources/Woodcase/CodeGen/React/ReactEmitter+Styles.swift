//
//  ReactEmitter+Styles.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Common Styles (transforms, opacity, enabled, blendMode)

    /// Emit styles from PenNodeCommon: transform, opacity, enabled, blendMode.
    ///
    /// A turned or flipped node's `transform` turns about `pivot`.
    static func emitCommonStyles(
        _ common: PenNodeCommon,
        blendMode: PenBlendMode?,
        pivot: TransformPivot
    ) -> [(String, String)] {
        var styles: [(String, String)] = []

        // Enabled
        if case .literal(false) = common.enabled {
            styles.append(("display", "\"none\""))
        }

        // Opacity
        if let opacity = common.opacity {
            styles.append(("opacity", emitPenValue(opacity)))
        }

        if let transform = DeltaTransform(of: common).cssFunctions {
            styles.append(("transform", "\"\(transform)\""))
            if let origin = pivot.transformOrigin {
                styles.append(("transformOrigin", "\"\(origin)\""))
            }
        }

        // Blend mode
        if let blendMode, blendMode != .normal {
            styles.append(("mixBlendMode", "\"\(mixBlendModeToCSSValue(blendMode))\""))
        }

        return styles
    }

    /// The CSS `<blend-mode>` keyword for `mode`, as `background-blend-mode` and an SVG
    /// `feBlend` take it.
    ///
    /// `<blend-mode>` has no linear burn or linear dodge: they take `color-burn` and
    /// `color-dodge`, the nearest (``warnApproximatedBlends(_:ctx:)`` says so). `light` is
    /// CSS's `lighten`, and a mode Woodcase does not know blends normally. An element's own
    /// blend takes ``mixBlendModeToCSSValue(_:)``, which has a true add.
    static func blendModeToCSSValue(_ mode: PenBlendMode) -> String {
        switch mode {
        case .linearBurn: "color-burn"
        case .linearDodge: "color-dodge"
        case .softLight: "soft-light"
        case .hardLight: "hard-light"
        case .colorBurn: "color-burn"
        case .colorDodge: "color-dodge"
        case .light: "lighten"
        case .unknown: "normal"
        default: mode.rawString
        }
    }

    /// The `mix-blend-mode` value for `mode`: the ``blendModeToCSSValue(_:)`` keyword, except
    /// linear dodge, which is `plus-lighter` — CSS Compositing Level 2's add, which
    /// `mix-blend-mode` alone takes (WebKit drops a `background-blend-mode` that names it)
    /// and Safari, Chrome and Firefox draw.
    static func mixBlendModeToCSSValue(_ mode: PenBlendMode) -> String {
        mode == .linearDodge ? "plus-lighter" : blendModeToCSSValue(mode)
    }

    // MARK: - Visual Styles (shared)

    /// Shared visual styles for fills, corner radius, stroke, and effects.
    /// Reused by rectangle, ellipse and browser; `box` and `ctx` serve a mesh fill.
    ///
    /// - Parameters:
    ///   - showsBackdrop: Whether a background blur shows through the node; `nil` asks
    ///     its fills (``PenFills/hasVisiblePaint``).
    ///   - layered: Whether the outer shadows are drawn by layers of their own
    ///     (``shadowLayerStyles(_:borderRadius:stroke:)``).
    static func emitVisualStyles(
        fills: PenFills?,
        box: FillBox,
        cornerRadius: PenCornerRadius?,
        stroke: (any PenStrokable)?,
        strokeDrawnByOverlay: Bool = false,
        effects: PenEffects?,
        showsBackdrop: Bool? = nil,
        layered: Bool = false,
        ctx: EmitContext
    ) -> [(String, String)] {
        var styles: [(String, String)] = []

        if let fills {
            styles.append(contentsOf: emitFillStyles(fills, box: box, ctx: ctx))
        }

        if let cornerRadius {
            if let cr = emitCornerRadius(cornerRadius) {
                styles.append(("borderRadius", cr))
            }
        }

        styles.append(contentsOf: emitStrokeAndEffects(
            stroke: stroke, strokeDrawnByOverlay: strokeDrawnByOverlay, effects: effects,
            showsBackdrop: showsBackdrop ?? (fills?.hasVisiblePaint == true), layered: layered
        ))

        return styles
    }

    // MARK: - Fill Styles

    /// Emit background styles for fills: returns [(key, value)] pairs.
    /// Handles solid colors, gradients, images, mesh gradients, multi-fill, enabled flag,
    /// blend modes. `box` sizes a mesh raster; `ctx` resolves and collects its themes.
    ///
    /// A paint blends only with the paints beneath it on its node (Ben's reading-1 ruling,
    /// 2026-10-20; `PenPaintStack`), which is what `background-blend-mode` does: a stack keeps
    /// each layer's mode there, and a lone fill, which has nothing beneath it, is written
    /// without one. A fill drawn by an element of its own carries its blend there
    /// (``fillLayers(_:box:beneathChildren:imageHref:ctx:)``).
    static func emitFillStyles(_ fills: PenFills, box: FillBox, ctx: EmitContext) -> [(String, String)] {
        let enabledFills = fills.all.filter(\.isEnabled)
        guard !enabledFills.isEmpty else { return [] }

        // Single simple color fill → backgroundColor
        if enabledFills.count == 1, let single = emitFillValue(enabledFills[0]) {
            return [("backgroundColor", single)]
        }

        // Single complex fill (gradient/image) → use background
        if enabledFills.count == 1 {
            return emitSingleComplexFill(enabledFills[0], box: box, ctx: ctx)
        }

        // Multiple fills → layer backgrounds
        var backgrounds: [String] = []
        var blendModes: [String] = []
        var colorLayers: Set<Int> = []
        for fill in enabledFills.reversed() {
            if let bg = emitFillAsBackgroundLayer(fill, box: box, ctx: ctx) {
                if fill.solidColor != nil { colorLayers.insert(backgrounds.count) }
                backgrounds.append(bg)
                blendModes.append(fill.blendMode.map(blendModeToCSSValue) ?? "normal")
            }
        }
        // CSS takes a bare color only in the bottom layer; anywhere else it drops the whole
        // declaration, so a color above another layer is a flat gradient.
        for index in backgrounds.indices.dropLast() where colorLayers.contains(index) {
            backgrounds[index] = "linear-gradient(\(backgrounds[index]), \(backgrounds[index]))"
        }

        guard !backgrounds.isEmpty else { return [] }
        var result = [("background", "\"\(backgrounds.joined(separator: ", "))\"")]
        if blendModes.contains(where: { $0 != "normal" }) {
            result.append(("backgroundBlendMode", "\"\(blendModes.joined(separator: ", "))\""))
        }
        return result
    }

    static func emitFillValue(_ fill: PenFill) -> String? {
        switch fill {
        case let .shorthand(color):
            if color.hasPrefix("$") {
                return "\"var(--\(color.dropFirst()))\""
            }
            return "\"\(color)\""
        case let .color(colorFill):
            switch colorFill.color {
            case let .literal(color): return "\"\(color)\""
            case let .variable(name): return "\"var(--\(name))\""
            }
        default:
            return nil
        }
    }

    static func emitSingleComplexFill(_ fill: PenFill, box: FillBox, ctx: EmitContext) -> [(String, String)] {
        switch fill {
        case .shorthand, .color:
            if let val = emitFillValue(fill) {
                return [("backgroundColor", val)]
            }
            return []
        case let .gradient(g):
            if let css = emitGradientCSS(g, box: box) {
                return [("background", "\"\(css)\"")]
            }
            return []
        case let .image(img):
            guard let url = img.url else { return [] }
            // Pen draws an image once: contain leaves the rest of the box empty, never tiled.
            return [
                ("backgroundImage", "\"url('\(url)')\""),
                ("backgroundSize", "\"\(cssImageSize(img.placement))\""),
                ("backgroundPosition", "\"center\""),
                ("backgroundRepeat", "\"no-repeat\""),
            ]
        case let .meshGradient(mesh):
            guard let layer = emitMeshLayer(mesh, box: box, ctx: ctx) else { return [] }
            return [("background", "\"\(layer)\"")]
        case .shader:
            // Shader fills are not executed; no background is emitted.
            return []
        case .unknown:
            return []
        }
    }

    static func emitFillAsBackgroundLayer(_ fill: PenFill, box: FillBox, ctx: EmitContext) -> String? {
        switch fill {
        case let .shorthand(color):
            color.hasPrefix("$") ? "var(--\(color.dropFirst()))" : color
        case let .color(c):
            switch c.color {
            case let .literal(v): v
            case let .variable(n): "var(--\(n))"
            }
        case let .gradient(g):
            emitGradientCSS(g, box: box)
        case let .image(img):
            img.url.map { "url('\($0)') center / \(cssImageSize(img.placement)) no-repeat" }
        case let .meshGradient(mesh):
            emitMeshLayer(mesh, box: box, ctx: ctx)
        case .shader:
            nil
        case .unknown:
            nil
        }
    }

    // MARK: - Corner Radius

    static func emitCornerRadius(_ cr: PenCornerRadius) -> String? {
        switch cr {
        case let .uniform(value):
            return emitPenValue(value)
        case let .perCorner(tl, tr, br, bl):
            let values = [tl, tr, br, bl].map { emitPenValueRaw($0) }
            return "\"\(values.joined(separator: " "))\""
        }
    }

    // MARK: - Padding

    static func emitPadding(_ padding: PenPadding) -> String? {
        switch padding {
        case let .uniform(value):
            return emitPenValue(value)
        case let .symmetric(h, v):
            return "\"\(emitPenValueRaw(v)) \(emitPenValueRaw(h))\""
        case let .individual(top, right, bottom, left):
            let values = [top, right, bottom, left].map { emitPenValueRaw($0) }
            return "\"\(values.joined(separator: " "))\""
        }
    }
}
