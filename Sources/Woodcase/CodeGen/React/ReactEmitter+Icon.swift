//
//  ReactEmitter+Icon.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Icon

    /// Writes an icon node as its package's component, imported from the path that draws
    /// its family and, for Material Symbols, its weight (``IconLibraryMapping/materialWeight(_:)``).
    static func emitIcon(
        _ node: PenNode,
        data: PenNode.IconData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)

        let family = data.library?.literalValue ?? "lucide"

        guard let iconName = data.icon?.literalValue else {
            ctx.lines.append("\(pad){/* missing icon name */}")
            return
        }

        guard let resolution = IconLibraryMapping.resolve(family: family, iconName: iconName, weight: data.weight?.literalValue) else {
            ctx.lines.append("\(pad){/* unsupported icon family: \(family) */}")
            return
        }

        let componentName = ctx.iconLocalName(resolution.componentName, family: family, importPath: resolution.importPath)
        warnSteppedMaterialWeight(node, data: data, family: family, ctx: ctx)

        // Determine size from width (icons are square)
        let size: Int? = if let w = data.width?.fixedValue {
            Int(w)
        } else {
            nil
        }

        let paint = iconPaint(data.fills, family: family, nodeID: node.id, ctx: ctx)

        var props: [String] = []
        if let size { props.append("size={\(size)}") }
        switch paint {
        case let .color(color):
            props.append("color=\"\(color)\"")
        case let .server(attribute, reference, _):
            props.append("\(attribute)=\"\(reference)\"")
        }

        // Add extra props from the library mapping (e.g. Phosphor weight)
        for (key, value) in resolution.extraProps.sorted(by: { $0.key < $1.key }) {
            props.append("\(key)=\"\(value)\"")
        }

        var iconStyles: [(String, String)] = []
        iconStyles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        iconStyles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
        iconStyles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))
        let innerShadows = iconInnerShadowFilters(
            NodeEffects(data.effects).innerShadows, size: data.width?.fixedValue, nodeID: node.id
        )
        iconStyles.append(contentsOf: filterEffectStyles(data.effects, leading: innerShadows.functions))

        // A paint server or an inner shadow's filter is defined beside the icon, the two
        // wrapped in a fragment so they stand anywhere one element does.
        var definitions = innerShadows.definitions
        if case let .server(_, _, paintDefinitions) = paint {
            definitions = paintDefinitions + definitions
        }
        var elementPad = pad
        if !definitions.isEmpty {
            ctx.lines.append("\(pad)<>")
            ctx.lines.append(contentsOf: hiddenDefinitions(definitions, pad: pad + "  "))
            elementPad += "  "
        }

        let propsStr = props.isEmpty ? "" : " \(props.joined(separator: " "))"
        if iconStyles.isEmpty {
            ctx.lines.append("\(elementPad)<\(componentName)\(propsStr) />")
        } else {
            ctx.lines.append("\(elementPad)<\(componentName)\(propsStr)")
            ctx.lines.append("\(elementPad)  style={{")
            for (key, value) in iconStyles {
                ctx.lines.append("\(elementPad)    \(key): \(value),")
            }
            ctx.lines.append("\(elementPad)  }}")
            ctx.lines.append("\(elementPad)/>")
        }
        if !definitions.isEmpty {
            ctx.lines.append("\(pad)</>")
        }
    }
}
