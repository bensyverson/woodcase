//
//  ReactEmitter+Frame.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Frame

    static func emitFrame(
        _ node: PenNode,
        data: PenNode.FrameData,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)

        // Build className
        let isNoneLayout = data.layout == .some(.none)
        var classes: [String] = isNoneLayout ? ["relative"] : ["flex"]

        if !isNoneLayout {
            // Check if any child has absolute positioning → add relative
            let hasAbsoluteChild = (data.children ?? []).contains { $0.common.layoutPosition == .absolute }
            if hasAbsoluteChild {
                classes.append("relative")
            }
            // Frame default layout is horizontal (matching pen format spec and PenLayoutEngine)
            switch data.layout {
            case .vertical: classes.append("flex-col")
            case .horizontal, nil: break // flex-row is CSS default; frame default is horizontal
            case .some(.none): break // handled above
            }
        }

        if let alignItems = data.alignItems {
            switch alignItems {
            case .center: classes.append("items-center")
            case .end: classes.append("items-end")
            case .start: break // default
            }
        }

        if let justifyContent = data.justifyContent {
            switch justifyContent {
            case .center: classes.append("justify-center")
            case .end: classes.append("justify-end")
            case .spaceBetween: classes.append("justify-between")
            case .spaceAround: classes.append("justify-around")
            case .start: break
            }
        }

        if let gap = data.gap, let gapValue = gap.literalValue {
            classes.append(tailwindGap(gapValue))
        }

        let hasChildren = !(data.children ?? []).isEmpty
        let overlay = strokeOverlayStyles(
            data, shape: .box(data.cornerRadius), beneathChildren: hasChildren,
            box: FillBox(width: data.width, height: data.height), ctx: ctx
        )
        let shadowLayers = layersShadows(node)
            ? shadowLayerStyles(data.effects, borderRadius: data.cornerRadius.flatMap(emitCornerRadius), stroke: data) : nil
        if overlay != nil || shadowLayers != nil, !classes.contains("relative") {
            classes.append("relative")
        }

        let classString = classes.joined(separator: " ")

        // Build style object
        var styles: [(String, String)] = []

        // Width
        let placement = ctx.placement(for: node.common)
        if let cssWidth = emitFrameSizing(
            data.width, axis: .width, of: data, placement: placement, parentLayout: parentLayout, isRoot: isRoot
        ) {
            styles.append(("width", cssWidth))
        }

        // Height
        if case .fillContainer = data.height, parentLayout == .vertical, placement == .flow {
            // In a column, fill_container height means "fill remaining space" —
            // use flex: 1 + minHeight: 0 so the element sizes correctly within
            // the parent. The parent's clip property handles overflow clipping.
            styles.append(("flex", "1"))
            styles.append(("minHeight", "0"))
        } else if let cssHeight = emitFrameSizing(
            data.height, axis: .height, of: data, placement: placement, parentLayout: parentLayout, isRoot: isRoot
        ) {
            styles.append(("height", cssHeight))
        }

        // Fill — check if this frame is an imageURL prop target
        let imageProp = component.props.first { prop in
            prop.type == .imageURL && prop.targetNodeID == node.id
        }
        if let imageProp {
            styles.append(("backgroundImage", "`url('${\(imageProp.name)}')`"))
            // Emit sizing/position from the original fill's mode
            if let fills = data.fills, let fill = fills.all.first, case let .image(img) = fill {
                let size = switch img.mode {
                case .fill, nil: "cover"
                case .fit: "contain"
                case .stretch: "100% 100%"
                }
                styles.append(("backgroundSize", "\"\(size)\""))
                styles.append(("backgroundPosition", "\"center\""))
            }
        } else if let fills = data.fills {
            styles.append(contentsOf: emitFillStyles(
                fills, box: FillBox(width: data.width, height: data.height), ctx: ctx
            ))
        }

        // Corner radius
        if let cornerRadius = data.cornerRadius {
            if let cr = emitCornerRadius(cornerRadius) {
                styles.append(("borderRadius", cr))
            }
        }

        // Padding
        if let padding = data.padding {
            if let pad = emitPadding(padding) {
                styles.append(("padding", pad))
            }
        }

        // Gap (variable)
        if let gap = data.gap, gap.variableName != nil {
            styles.append(("gap", emitPenValue(gap)))
        }

        // Clip
        if case .literal(true) = data.clip {
            styles.append(("overflow", "\"hidden\""))
        }

        // Absolute positioning
        if node.common.layoutPosition == .absolute {
            styles.append(("position", "\"absolute\""))
            if let x = node.common.x {
                styles.append(("left", emitPenValue(x)))
            }
            if let y = node.common.y {
                styles.append(("top", emitPenValue(y)))
            }
        }

        // Stroke + Effects (merged to combine boxShadow values)
        styles.append(contentsOf: emitStrokeAndEffects(
            stroke: data, effects: data.effects,
            showsBackdrop: data.fills?.hasVisiblePaint == true, layered: shadowLayers != nil
        ))

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

        // Isolation: create stacking context when children use fill-level blend modes
        // Isolation also keeps a stroke overlay's negative z-index above the frame's background.
        if (data.children ?? []).contains(where: { nodeHasFillBlendMode($0) }) || (overlay != nil && hasChildren) {
            styles.append(("isolation", "\"isolate\""))
        }

        // var() substitution for state-affected properties
        substituteStateVars(&styles, pivot: ctx.transformPivot(for: node.common), ctx: ctx)

        // Resolve semantic tag + extra attributes for root elements
        let tag: String
        var extraAttrs: [String] = []
        if isRoot, let role = component.role {
            switch role {
            case .button:
                tag = "button"
                extraAttrs.append("type=\"button\"")
            case .link:
                tag = "a"
            case .toggle:
                tag = "button"
                extraAttrs.append("role=\"switch\"")
                extraAttrs.append("aria-checked={checked}")
            case .tabBar:
                tag = "nav"
                extraAttrs.append("role=\"tablist\"")
            case .textInput, .select:
                tag = "div"
            }

            // Role-derived attributes — only emit disabled on elements that support it
            if role.knownStates.contains("disabled"), tag == "button" {
                extraAttrs.append("disabled={disabled}")
            }
            if role == .link {
                extraAttrs.append("href={href}")
            }

            // Toggle: wire checked prop to data attributes for state CSS.
            // Only emit for designer-override states that produce actual CSS rules.
            if role == .toggle {
                for state in component.states where !state.isStructural && state.source != .smartDefault {
                    if case let .attribute(name, _) = state.trigger {
                        let isOffState = state.name == "off"
                        let condition = isOffState
                            ? "!checked ? \"true\" : undefined"
                            : "checked ? \"true\" : undefined"
                        extraAttrs.append("data-\(name)={\(condition)}")
                    }
                }
            }
        } else {
            tag = "div"
        }
        let attrString = extraAttrs.isEmpty ? "" : " " + extraAttrs.joined(separator: " ")

        // Emit element
        if isRoot {
            // Prepend stateClassName if present
            let fullClass: String = if let sc = ctx.stateClassName {
                "\(sc) \(classString)"
            } else {
                classString
            }
            ctx.lines.append("\(pad)<\(tag)\(attrString)")
            ctx.lines.append("\(pad)  className={cn(\"\(fullClass)\", className)}")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in styles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)    ...style,")
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
        } else if styles.isEmpty {
            ctx.lines.append("\(pad)<div className=\"\(classString)\">")
        } else {
            ctx.lines.append("\(pad)<div")
            ctx.lines.append("\(pad)  className=\"\(classString)\"")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in styles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
        }

        if let shadowLayers {
            emitShadowLayers(shadowLayers, indent: indent + 2, ctx: ctx)
        }
        if let overlay {
            emitStrokeOverlay(overlay, indent: indent + 2, ctx: ctx)
        }

        // Children
        let savedPlacement = ctx.childPlacement
        ctx.childPlacement = isNoneLayout ? .free : .flow
        defer { ctx.childPlacement = savedPlacement }
        let turnedFillSizes = TurnedFillSizes(container: data)
        for child in data.children ?? [] {
            ctx.turnedFillSizes = turnedFillSizes
            // Track node path for state var substitution
            let savedPath = ctx.currentNodePath
            if let childName = child.common.name {
                ctx.currentNodePath = savedPath == "." ? childName : "\(savedPath)/\(childName)"
            }

            if isNoneLayout {
                // layout: none → children are free-positioned (absolute)
                let childPad = String(repeating: " ", count: indent + 2)
                var posStyles = [("position", "\"absolute\"")]
                if let x = child.common.x { posStyles.append(("left", emitPenValue(x))) }
                if let y = child.common.y { posStyles.append(("top", emitPenValue(y))) }
                ctx.lines.append("\(childPad)<div")
                ctx.lines.append("\(childPad)  style={{")
                for (key, value) in posStyles {
                    ctx.lines.append("\(childPad)    \(key): \(value),")
                }
                ctx.lines.append("\(childPad)  }}")
                ctx.lines.append("\(childPad)>")
                emitNode(child, component: component, indent: indent + 4, ctx: ctx, isRoot: false, parentLayout: data.layout)
                ctx.lines.append("\(childPad)</div>")
            } else {
                emitNode(child, component: component, indent: indent + 2, ctx: ctx, isRoot: false, parentLayout: data.layout)
            }

            ctx.currentNodePath = savedPath
        }

        // Root uses semantic tag; non-root always uses div
        let closingTag = isRoot ? tag : "div"
        ctx.lines.append("\(pad)</\(closingTag)>")
    }

    // MARK: - Group

    /// Emits a `group`: a transparent container whose children are always
    /// positioned at their own explicit x/y (there is no group-level layout
    /// to opt into), so it only needs `relative` to anchor them — mirroring
    /// how ``emitFrame(_:data:component:indent:ctx:isRoot:parentLayout:)``
    /// handles a frame with `layout: "none"`.
    ///
    /// `isRoot` is accepted for call-site symmetry with the other `emit*`
    /// functions but unused: unlike a frame, a root group does not yet pick
    /// up the semantic tag, `className={cn(...)}`/`...style` prop-spreading,
    /// or role-derived attributes a component root gets.
    static func emitGroup(
        _ node: PenNode,
        data: PenNode.GroupData,
        component: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot _: Bool
    ) {
        let pad = String(repeating: " ", count: indent)
        let classString = "relative"

        var styles: [(String, String)] = []

        // Absolute positioning
        if node.common.layoutPosition == .absolute {
            styles.append(("position", "\"absolute\""))
            if let x = node.common.x {
                styles.append(("left", emitPenValue(x)))
            }
            if let y = node.common.y {
                styles.append(("top", emitPenValue(y)))
            }
        }

        // Common: transforms, opacity, enabled, blendMode
        styles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: .anchor))

        // The group's shadows and blur over its content, an approximation of Pen's silhouette
        styles.append(contentsOf: filterEffectStyles(data.effects))

        if styles.isEmpty {
            ctx.lines.append("\(pad)<div className=\"\(classString)\">")
        } else {
            ctx.lines.append("\(pad)<div")
            ctx.lines.append("\(pad)  className=\"\(classString)\"")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in styles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
        }

        let savedPlacement = ctx.childPlacement
        ctx.childPlacement = .free
        defer { ctx.childPlacement = savedPlacement }
        for child in data.children ?? [] {
            // Track node path for state var substitution
            let savedPath = ctx.currentNodePath
            if let childName = child.common.name {
                ctx.currentNodePath = savedPath == "." ? childName : "\(savedPath)/\(childName)"
            }

            // Children are always free-positioned (absolute), like a frame with layout: none.
            let childPad = String(repeating: " ", count: indent + 2)
            var posStyles = [("position", "\"absolute\"")]
            if let x = child.common.x { posStyles.append(("left", emitPenValue(x))) }
            if let y = child.common.y { posStyles.append(("top", emitPenValue(y))) }
            ctx.lines.append("\(childPad)<div")
            ctx.lines.append("\(childPad)  style={{")
            for (key, value) in posStyles {
                ctx.lines.append("\(childPad)    \(key): \(value),")
            }
            ctx.lines.append("\(childPad)  }}")
            ctx.lines.append("\(childPad)>")
            emitNode(child, component: component, indent: indent + 4, ctx: ctx, isRoot: false)
            ctx.lines.append("\(childPad)</div>")

            ctx.currentNodePath = savedPath
        }

        ctx.lines.append("\(pad)</div>")
    }
}
