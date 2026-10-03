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
            styles.append(("mixBlendMode", "\"\(blendModeToCSSValue(blendMode))\""))
        }

        return styles
    }

    static func blendModeToCSSValue(_ mode: PenBlendMode) -> String {
        switch mode {
        case .linearBurn: "color-burn" // CSS approximation
        case .linearDodge: "color-dodge" // CSS approximation
        case .softLight: "soft-light"
        case .hardLight: "hard-light"
        case .colorBurn: "color-burn"
        case .colorDodge: "color-dodge"
        default: mode.rawString
        }
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
            stroke: stroke, effects: effects,
            showsBackdrop: showsBackdrop ?? (fills?.hasVisiblePaint == true), layered: layered
        ))

        return styles
    }

    // MARK: - Fill Styles

    /// Emit background styles for fills: returns [(key, value)] pairs.
    /// Handles solid colors, gradients, images, mesh gradients, multi-fill, enabled flag,
    /// blend modes. `box` sizes a mesh raster; `ctx` resolves and collects its themes.
    static func emitFillStyles(_ fills: PenFills, box: FillBox, ctx: EmitContext) -> [(String, String)] {
        let enabledFills = fills.all.filter(\.isEnabled)
        guard !enabledFills.isEmpty else { return [] }

        // Single simple color fill → backgroundColor
        if enabledFills.count == 1, let single = emitFillValue(enabledFills[0]) {
            var result = [("backgroundColor", single)]
            if let blendMode = enabledFills[0].blendMode, blendMode != .normal {
                result.append(("mixBlendMode", "\"\(blendModeToCSSValue(blendMode))\""))
            }
            return result
        }

        // Single complex fill (gradient/image) → use background
        if enabledFills.count == 1 {
            var result = emitSingleComplexFill(enabledFills[0], box: box, ctx: ctx)
            if let blendMode = enabledFills[0].blendMode, blendMode != .normal {
                result.append(("mixBlendMode", "\"\(blendModeToCSSValue(blendMode))\""))
            }
            return result
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

    /// Check if a node has any fill-level blend mode (not node-level).
    static func nodeHasFillBlendMode(_ node: PenNode) -> Bool {
        let fills: PenFills? = switch node.kind {
        case let .frame(d): d.fills
        case let .rectangle(d): d.fills
        case let .ellipse(d): d.fills
        default: nil
        }
        guard let fills else { return false }
        return fills.all.contains { fill in
            if let mode = fill.blendMode, mode != .normal { return true }
            return false
        }
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
            var styles = [("backgroundImage", "\"url('\(url)')\"")]
            let size = switch img.placement {
            case .cover: "cover"
            case .contain: "contain"
            case .stretch: "100% 100%"
            }
            styles.append(("backgroundSize", "\"\(size)\""))
            styles.append(("backgroundPosition", "\"center\""))
            return styles
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
            img.url.map { "url('\($0)')" }
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
