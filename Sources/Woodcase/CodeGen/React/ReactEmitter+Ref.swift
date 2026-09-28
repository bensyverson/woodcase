//
//  ReactEmitter+Ref.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Ref

    static func emitRef(
        _ node: PenNode,
        data: PenNode.RefData,
        indent: Int,
        ctx: EmitContext,
        isRoot _: Bool
    ) {
        let pad = String(repeating: " ", count: indent)

        // TabBar variant ref resolution: redirect to base component with selected prop
        if let mapping = ctx.variantToState[data.ref] {
            ctx.componentRefs.insert(mapping.componentName)
            ctx.lines.append("\(pad)<\(mapping.componentName) selected=\"\(mapping.stateName)\" />")
            return
        }

        let component = ctx.componentRegistry[data.ref]
        let componentName: String = if let component {
            component.name
        } else {
            CodeGenName.typeName(node.common.name ?? data.ref)
        }

        // Determine if any descendant overrides are unmapped (no corresponding prop)
        let hasUnmappedOverrides: Bool = if let descendants = data.descendants, let component {
            hasUnmapped(overrides: descendants, in: component)
        } else {
            false
        }

        if hasUnmappedOverrides, let component {
            emitInlinedRef(
                node, data: data, component: component,
                componentName: componentName, indent: indent, ctx: ctx
            )
        } else {
            // Track this component reference so an import is generated
            if component != nil {
                ctx.componentRefs.insert(componentName)
            }
            emitComponentRef(
                node, data: data, componentName: componentName,
                component: component, indent: indent, ctx: ctx
            )
        }
    }

    /// Checks whether any descendant override keys lack a prop mapping.
    ///
    /// A key is mapped when *any* prop reads that node, so a descendant several props
    /// share is mapped like any other — the ambiguity between them is a `lint` finding,
    /// not a reason to inline the whole component.
    private static func hasUnmapped(
        overrides: [String: PenDescendantOverride],
        in component: ComponentDefinition
    ) -> Bool {
        let lookup = component.propsByNodeID
        for nodeID in overrides.keys {
            if lookup[nodeID] == nil {
                return true
            }
        }
        return false
    }

    /// Emit a component reference tag with mapped props (existing behavior).
    private static func emitComponentRef(
        _: PenNode,
        data: PenNode.RefData,
        componentName: String,
        component: ComponentDefinition?,
        indent: Int,
        ctx: EmitContext
    ) {
        let pad = String(repeating: " ", count: indent)

        // Map descendant overrides to props
        var propAttrs: [String] = []
        if let descendants = data.descendants, let component {
            let mapped = PropMapper.map(overrides: descendants, to: component)
            for prop in mapped {
                propAttrs.append("\(prop.name)=\(jsxAttributeValue(prop.value))")
            }
        }

        // Map root overrides to style prop
        var rootStyles = emitRootOverrideStyles(data.rootOverrides)

        // Component roots skip flexShrink in emitFlexShrink (isRoot == true),
        // so apply it here when the component's source root has fixed dimensions.
        if let component, case let .frame(frameData) = component.sourceNode.kind {
            let hasFixedWidth = frameData.width?.fixedValue != nil
            let hasFixedHeight = frameData.height?.fixedValue != nil
            if hasFixedWidth || hasFixedHeight {
                rootStyles.append(("flexShrink", "0"))
            }
        }

        if rootStyles.isEmpty {
            let propsStr = propAttrs.isEmpty ? "" : " \(propAttrs.joined(separator: " "))"
            ctx.lines.append("\(pad)<\(componentName)\(propsStr) />")
        } else {
            let propsStr = propAttrs.isEmpty ? "" : " \(propAttrs.joined(separator: " "))"
            ctx.lines.append("\(pad)<\(componentName)\(propsStr)")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in rootStyles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)/>")
        }
    }

    /// Inline a component by cloning its source node, applying overrides, and emitting the tree.
    private static func emitInlinedRef(
        _ node: PenNode,
        data: PenNode.RefData,
        component: ComponentDefinition,
        componentName: String,
        indent: Int,
        ctx: EmitContext
    ) {
        let pad = String(repeating: " ", count: indent)

        // Clone the component's source node
        var patched = component.sourceNode

        // Apply root overrides
        if let rootOverrides = data.rootOverrides, !rootOverrides.isEmpty {
            patched = PenNodePatcher.patchNode(patched, with: rootOverrides)
        }

        // Apply all descendant overrides
        if let descendants = data.descendants {
            patched = PenNodePatcher.applyOverrides(to: patched, overrides: descendants)
        }

        // Emit comment indicating inlining
        ctx.lines.append("\(pad){/* Customized from: \(componentName) */}")

        // Build a dummy component (no props) for the inlined emission
        let dummyComp = ComponentDefinition(
            id: component.id,
            name: componentName,
            sourceNode: patched,
            props: [],
            actions: [],
            bindings: []
        )

        // Emit the patched node tree
        emitNode(patched, component: dummyComp, indent: indent, ctx: ctx, isRoot: false)

        // Emit diagnostic
        let severity: PenDiagnostic.Severity = ctx.options.strict ? .error : .warning
        let unmappedIDs = unmappedOverrideIDs(data.descendants, in: component)
        let message = "Inlined component '\(componentName)' due to unmapped descendant overrides: \(unmappedIDs.sorted().joined(separator: ", "))"
        ctx.diagnostics?.add(PenDiagnostic(
            severity: severity,
            stage: .codeGen,
            message: message,
            nodeID: node.id
        ))
    }

    /// Returns the set of override node IDs that have no corresponding prop in the component.
    private static func unmappedOverrideIDs(
        _ overrides: [String: PenDescendantOverride]?,
        in component: ComponentDefinition
    ) -> [String] {
        guard let overrides else { return [] }
        let lookup = component.propsByNodeID
        return overrides.keys.filter { lookup[$0] == nil }
    }

    static func emitRootOverrideStyles(
        _ overrides: [String: AnyCodable]?
    ) -> [(String, String)] {
        guard let overrides else { return [] }
        var styles: [(String, String)] = []

        for (key, value) in overrides.sorted(by: { $0.key < $1.key }) {
            switch key {
            case "width", "height":
                if let css = emitAnyCodableSizing(value) {
                    styles.append((key, css))
                }
            case "cornerRadius":
                if let css = emitAnyCodableSizing(value) {
                    styles.append(("borderRadius", css))
                }
            case "fill":
                if case let .string(s) = value {
                    if s.hasPrefix("$") {
                        styles.append(("backgroundColor", "\"var(--\(s.dropFirst()))\""))
                    } else {
                        styles.append(("backgroundColor", "\"\(s)\""))
                    }
                }
            default:
                break
            }
        }

        return styles
    }

    static func emitAnyCodableSizing(_ value: AnyCodable) -> String? {
        switch value {
        case let .double(v):
            if v == v.rounded(), !v.isInfinite {
                return String(Int(v))
            }
            return String(v)
        case let .int(v):
            return String(v)
        case let .string(s):
            if s == "fill_container" { return "\"100%\"" }
            if s == "fit_content" { return "\"fit-content\"" }
            if s.hasPrefix("$") {
                return "\"var(--\(s.dropFirst()))\""
            }
            return "\"\(s)\""
        default:
            return nil
        }
    }
}
