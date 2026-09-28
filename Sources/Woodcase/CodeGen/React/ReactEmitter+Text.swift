//
//  ReactEmitter+Text.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Text

    static func emitText(
        _ node: PenNode,
        data: PenNode.TextData,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)

        // Build style
        var styles: [(String, String)] = []

        // Fill: a colour, or paint clipped to the glyphs
        styles.append(contentsOf: textPaintStyles(data, nodeBlendMode: data.blendMode, ctx: ctx))

        // Font
        if let fontFamily = data.fontFamily {
            styles.append(("fontFamily", emitFontFamily(fontFamily)))
        }
        if let fontSize = data.fontSize {
            styles.append(("fontSize", emitPenValue(fontSize)))
        }
        if let fontWeight = data.fontWeight {
            styles.append(("fontWeight", emitFontWeight(fontWeight)))
        }
        if let fontStyle = data.fontStyle {
            styles.append(("fontStyle", emitPenValue(fontStyle)))
        }
        if let letterSpacing = data.letterSpacing {
            styles.append(("letterSpacing", emitPenValue(letterSpacing)))
        }
        // Line height, optical size, wrapping and vertical alignment, as Pen sets lines
        styles.append(contentsOf: textLayoutStyles(data, theme: ctx.theme))

        // Text alignment
        if let textAlign = data.textAlign {
            styles.append(("textAlign", "\"\(textAlign.rawValue)\""))
        }

        // Text decorations
        var decorations: [String] = []
        if case .literal(true) = data.underline { decorations.append("underline") }
        if case .literal(true) = data.strikethrough { decorations.append("line-through") }
        if !decorations.isEmpty {
            styles.append(("textDecoration", "\"\(decorations.joined(separator: " "))\""))
        }

        // Width/height from textGrowth
        if let textGrowth = data.textGrowth, textGrowth == .fixedWidth || textGrowth == .fixedWidthHeight {
            if let width = data.width, let cssWidth = emitSizing(width) {
                styles.append(("width", cssWidth))
            }
            styles.append(("overflowWrap", "\"break-word\""))
        }
        if let textGrowth = data.textGrowth, textGrowth == .fixedWidthHeight {
            if let height = data.height, let cssHeight = emitSizing(height) {
                styles.append(("height", cssHeight))
            }
        }

        // Flex-shrink for fixed-size children
        styles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))

        // Common: transforms, opacity, enabled, blendMode
        styles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
        styles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))

        // Shadows cast by the glyphs, and layer blur
        let painted = styles.contains { $0.0 == "backgroundClip" }
        styles.append(contentsOf: textEffectStyles(data.effects, painted: painted))

        // var() substitution for state-affected properties
        substituteStateVars(&styles, pivot: ctx.transformPivot(for: node.common), ctx: ctx)

        // Check if this text is a prop target
        let propForNode = component.props.first { prop in
            let pathSegments = prop.path.split(separator: "/")
            return pathSegments.last.map(String.init) == node.common.name
        }

        // Determine element tag
        let tag: String = data.href != nil ? "a" : "p"
        let hrefAttr = if let href = data.href { " href=\"\(href)\"" } else { "" }

        // Empty text: reserve space matching font metrics
        let textContent = extractTextContent(data) ?? ""
        if textContent.trimmingCharacters(in: .whitespaces).isEmpty {
            let fontSize = data.fontSize?.literalValue ?? PenTextMeasurer.defaultFontSize
            let pitch: Double? = if let lineHeight = data.lineHeight {
                lineHeight.literalValue.map { fontSize * $0 }
            } else {
                naturalLinePitch(data, theme: ctx.theme)
            }
            // With neither, the `&nbsp;` below holds the browser's own line.
            if let pitch {
                styles.append(("minHeight", "\(Int(pitch))"))
            }
        }

        let rawContent: String = if let prop = propForNode {
            "{\(prop.name)}"
        } else {
            jsxTextChild(textContent)
        }
        // Use &nbsp; for empty content to prevent HTML whitespace collapse
        let content = rawContent.trimmingCharacters(in: .whitespaces).isEmpty && propForNode == nil
            ? "&nbsp;"
            : rawContent

        if styles.isEmpty {
            ctx.lines.append("\(pad)<\(tag)\(hrefAttr)>")
            ctx.lines.append("\(pad)  \(content)")
            ctx.lines.append("\(pad)</\(tag)>")
        } else {
            ctx.lines.append("\(pad)<\(tag)\(hrefAttr)")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in styles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
            ctx.lines.append("\(pad)  \(content)")
            ctx.lines.append("\(pad)</\(tag)>")
        }
    }

    // MARK: - Text Content

    /// The literal text of a text node, or nil when the content is absent or an
    /// unresolved variable reference.
    static func extractTextContent(_ data: PenNode.TextData) -> String? {
        data.content?.literalValue
    }
}
