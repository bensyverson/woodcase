//
//  SwiftUINodeEmitter+Effects.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A node's enabled effects that the emitter can write, sorted by where they draw,
    /// and the properties it cannot.
    ///
    /// Radii are already SwiftUI's: a shadow's `radius` and a blur's are the Gaussian's
    /// sigma, which is half of Pen's `blur` and `radius` (the renderer's rule, and what
    /// SwiftUI's `shadow(radius:)` and `blur(radius:)` measure against Pen's exports).
    struct Effects: Friendly {
        /// One shadow, in SwiftUI's terms.
        struct Shadow: Friendly {
            /// The color expression.
            var color: String
            /// The Gaussian's sigma, in points; a literal or a theme read.
            var radius: SwiftUINumber
            /// The offset, in points; a literal or a theme read.
            var x: SwiftUINumber
            /// The offset, in points; a literal or a theme read.
            var y: SwiftUINumber
            /// The SwiftUI blend mode, or `nil` for normal.
            var blendMode: String?

            /// The arguments after the shape: `color: …, radius: 4, x: 4, y: 4`, the offset
            /// and blend mode only when set. An offset that is a theme read is always
            /// written, since it may be nonzero under a theme this build cannot rule out.
            var arguments: String {
                var parts = ["color: \(color)", "radius: \(radius.code)"]
                if !x.isZero || !y.isZero {
                    parts += ["x: \(x.code)", "y: \(y.code)"]
                }
                if let blendMode {
                    parts.append("blendMode: .\(blendMode)")
                }
                return parts.joined(separator: ", ")
            }

            /// The support file's `[PenShadowStyle(…), …]` for `shadows`, in order.
            static func styles(_ shadows: [Shadow]) -> String {
                "[" + shadows.map { "PenShadowStyle(\($0.arguments))" }.joined(separator: ", ") + "]"
            }
        }

        /// Outer shadows, in Pen's array order: the first is drawn lowest.
        var outer: [Shadow] = []
        /// Inner shadows, in Pen's array order.
        var inner: [Shadow] = []
        /// Layer blurs' sigmas, in points; a literal or a theme read.
        var blurs: [SwiftUINumber] = []
        /// Background blurs' Pen radii, in points; a literal or a theme read.
        var backgroundBlurs: [SwiftUINumber] = []
        /// What was left out, for the node's warning.
        var unemitted: [String] = []
    }

    /// Sort `effects` by kind, dropping the disabled ones and naming any that uses a color
    /// or number variable the theme lacks, or a type this build does not know. A color or
    /// number variable that the theme has is read through it.
    func effects(_ effects: PenEffects?) -> Effects {
        var result = Effects()
        for effect in effects?.all ?? [] {
            switch effect {
            case let .shadow(shadow):
                guard shadow.enabled?.literalValue != false else { continue }
                guard let parsed = self.shadow(shadow, unemitted: &result.unemitted) else { continue }
                if shadow.shadowType == .inner {
                    result.inner.append(parsed)
                } else {
                    result.outer.append(parsed)
                }
            case let .blur(blur):
                guard blur.enabled?.literalValue != false else { continue }
                guard let radius = number(blur.radius, unemitted: &result.unemitted) else { continue }
                if !radius.isZero { result.blurs.append(radius.halved) }
            case let .backgroundBlur(blur):
                guard blur.enabled?.literalValue != false else { continue }
                guard let radius = number(blur.radius, unemitted: &result.unemitted) else { continue }
                if !radius.isZero { result.backgroundBlurs.append(radius) }
            case let .unknown(typeName, _):
                result.unemitted.append("\(typeName) effects")
            }
        }
        return result
    }

    /// The inner-shadow layers for a node drawn in `shape`: an overlay on a leaf, or,
    /// for a frame with children, a background placed between its fills and its
    /// content, where Pen draws it.
    func innerShadows(_ effects: PenEffects?, in shape: Outline, underContent: Bool) -> [SwiftUIViewCode.Modifier] {
        // An even-odd shape — a ring — is clipped even-odd, or its hole counts as inside.
        let rule = shape.evenOdd ? ", eoFill: true" : ""
        return self.effects(effects).inner.map { shadow in
            if underContent {
                SwiftUIViewCode.Modifier(
                    ".background",
                    content: [SwiftUIViewCode(head: "PenInnerShadow(\(shape.view), \(shadow.arguments)\(rule))")]
                )
            } else {
                SwiftUIViewCode.Modifier(".penInnerShadow(\(shape.view), \(shadow.arguments)\(rule))")
            }
        }
    }

    /// `view` with a text's background blur, outer shadows and layer blur: everything but
    /// its inner shadows, which go with its paint. Any other node gets none here: a shape
    /// or a frame is given its own where it is drawn (``filledShape(_:shape:fills:stroke:effects:in:unemitted:)``,
    /// ``frame(_:data:in:)``), which alone knows the box its stroke band is laid out in, and
    /// a placeholder gets none.
    func withEffects(_ view: SwiftUIViewCode, of node: PenNode) -> SwiftUIViewCode {
        guard case let .text(data) = node.kind else { return view }
        return withEffects(view, of: node, effects: data.effects, fills: data.fills, silhouette: nil)
    }

    /// `view` composited with `node`'s blend mode — outermost, so its shadows and opacity
    /// blend with it, as the renderer blends them. A mode this build does not know, or one
    /// on a node that is a placeholder, is left out.
    func blended(_ view: SwiftUIViewCode, _ node: PenNode) -> SwiftUIViewCode {
        let mode: PenBlendMode? = switch node.kind {
        case let .frame(data): data.blendMode
        case let .rectangle(data): data.blendMode
        case let .ellipse(data): shapeDrawn(node) ? data.blendMode : nil
        case let .text(data): data.blendMode
        case let .path(data): shapeDrawn(node) ? data.blendMode : nil
        case let .polygon(data): shapeDrawn(node) ? data.blendMode : nil
        case let .line(data): shapeDrawn(node) ? data.blendMode : nil
        case let .icon(data): iconOutline(data) != nil ? data.blendMode : nil
        case let .group(data): data.blendMode
        default: nil
        }
        guard let mode, mode != .normal else { return view }
        guard let name = SwiftUIBlendMode.name(for: mode) else {
            warnUnemitted(node, ["the blend mode \(SwiftUILiteral.string(mode.rawString))"])
            return view
        }
        return view.modified(".blendMode(.\(name))")
    }

    /// Whether a shape node is drawn rather than a placeholder: a plain ellipse, or a
    /// geometry whose outline exists.
    private func shapeDrawn(_ node: PenNode) -> Bool {
        if case let .ellipse(data) = node.kind, !isArc(data) { return true }
        return geometryOutline(node) != nil
    }

    /// `view` with the background blur, outer shadows and layer blur of `penEffects`,
    /// warning for what it leaves out. `silhouette` is what the node's shadows are cast by
    /// and its outline, or `nil` for text, whose glyphs cast its shadow; a text's inner
    /// shadows go with its paint (``text(_:data:in:)``).
    func withEffects(
        _ view: SwiftUIViewCode, of node: PenNode, effects penEffects: PenEffects?, fills: PenFills?, silhouette: Silhouette?
    ) -> SwiftUIViewCode {
        var effects = effects(penEffects)
        var view = view
        if !effects.backgroundBlurs.isEmpty, fills?.hasVisiblePaint == true {
            if let shape = silhouette?.outline {
                for radius in effects.backgroundBlurs {
                    view = view.modified(".penBackgroundBlur(\(shape.view), radius: \(radius.code))")
                }
                let label = node.common.name ?? node.id
                diagnostics?.warn(
                    "SwiftUI has no backdrop blur of a set radius; \"\(label)\"'s background blur is a Material, which only approximates it",
                    stage: .codeGen, nodeID: node.id
                )
            } else {
                effects.unemitted.append("background blur on text")
            }
        }
        // A later `.background` draws under an earlier one, so the first shadow goes last.
        for shadow in effects.outer.reversed() {
            if let silhouette {
                view = view.modified(
                    ".penDropShadow(\(silhouette.cast), \(shadow.arguments)\(silhouette.outsetArgument)\(silhouette.eoFillArgument))"
                )
            } else {
                view = view.modified(".shadow(\(shadow.arguments))")
            }
        }
        for radius in effects.blurs {
            view = view.modified(".blur(radius: \(radius.code))")
        }
        warnUnemitted(node, effects.unemitted)
        return view
    }

    /// A drawn shadow, or `nil` when a number or color it needs cannot be written (reported
    /// in `unemitted`): a blur or offset naming a variable the theme has no number for, or a
    /// color variable it has no color for. A number the theme has is read through it.
    private func shadow(_ shadow: PenEffect.PenShadowEffect, unemitted: inout [String]) -> Effects.Shadow? {
        guard let blur = number(shadow.blur, unemitted: &unemitted) else { return nil }
        let x: SwiftUINumber?
        let y: SwiftUINumber?
        if let offset = shadow.offset {
            x = number(offset.x, unemitted: &unemitted)
            y = number(offset.y, unemitted: &unemitted)
        } else {
            (x, y) = (SwiftUINumber(0), SwiftUINumber(0))
        }
        guard let x, let y else { return nil }
        let color: String
        switch shadow.color {
        case let .variable(name)?:
            guard let read = colorCode(.variable(name), unemitted: &unemitted) else { return nil }
            color = read.code
        case let .literal(hex)?:
            // A color that does not parse draws the default, as the renderer does.
            guard let parsed = PenHexColor(hex) ?? PenHexColor(Self.defaultShadowColor) else { return nil }
            color = SwiftUILiteral.color(parsed)
        case nil:
            guard let parsed = PenHexColor(Self.defaultShadowColor) else { return nil }
            color = SwiftUILiteral.color(parsed)
        }
        let blendMode = shadow.blendMode.flatMap { $0 == .normal ? nil : SwiftUIBlendMode.name(for: $0) }
        return Effects.Shadow(color: color, radius: blur.halved, x: x, y: y, blendMode: blendMode)
    }

    /// The color of a shadow that names none: half-transparent black, the renderer's.
    private static let defaultShadowColor = "#00000080"
}
