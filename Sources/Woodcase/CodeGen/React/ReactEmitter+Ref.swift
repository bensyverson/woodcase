//
//  ReactEmitter+Ref.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Ref

    /// An instance: a call to its component — `<Card title="Revenue" />`, with a prop per
    /// slot the instance fills (``ReactSlot``) — or, when it overrides what no prop
    /// carries, the component inlined with a warning.
    ///
    /// - Parameters:
    ///   - node: The `ref` node.
    ///   - data: Its payload.
    ///   - enclosing: The component (or a page's stand-in) whose markup the instance is part
    ///     of, which a slot fill's content is drawn in.
    ///   - indent: Its indentation, in spaces.
    ///   - ctx: The file's context.
    /// - Returns: The steps left: a fill's content, or the inlined tree.
    static func emitRef(
        _ node: PenNode,
        data: PenNode.RefData,
        component enclosing: ComponentDefinition,
        indent: Int,
        ctx: EmitContext,
        isRoot _: Bool
    ) -> [ReactEmitStep] {
        let pad = String(repeating: " ", count: indent)

        // TabBar variant ref resolution: redirect to base component with selected prop
        if let mapping = ctx.variantToState[data.ref] {
            ctx.componentRefs.insert(mapping.componentName)
            ctx.lines.append("\(pad)<\(mapping.componentName) selected=\"\(mapping.stateName)\" />")
            return []
        }

        let component = ctx.componentRegistry[data.ref]
        let componentName: String = if let component {
            component.name
        } else {
            CodeGenName.typeName(node.common.name ?? data.ref)
        }

        // The slots the instance fills, by slot frame id, which the call passes as props.
        let slots = component.map(ReactSlot.slots(of:)) ?? []
        let fills: [String: [PenNode]] = if let component, !slots.isEmpty {
            InstanceOverrides(of: data, against: component, slots: Set(slots.map(\.frame.id))).slotFills
        } else {
            [:]
        }

        // Determine if any descendant overrides are unmapped (no corresponding prop)
        let hasUnmappedOverrides: Bool = if let descendants = data.descendants, let component {
            hasUnmapped(overrides: descendants, in: component, fills: fills)
        } else {
            false
        }

        if hasUnmappedOverrides, let component {
            return emitInlinedRef(
                node, data: data, component: component,
                componentName: componentName, indent: indent, ctx: ctx
            )
        } else {
            // Track this component reference so an import is generated
            if component != nil {
                ctx.componentRefs.insert(componentName)
            }
            let call = ComponentCall(name: componentName, component: component, slots: slots, fills: fills)
            return emitComponentRef(data: data, call: call, enclosing: enclosing, indent: indent, ctx: ctx)
        }
    }

    /// The call an instance makes: the component, and the content it passes its slots.
    private struct ComponentCall {
        /// The component's name in the emitted code.
        var name: String
        /// The component, when the module declares it.
        var component: ComponentDefinition?
        /// The component's slots, in order.
        var slots: [ReactSlot]
        /// The instance's content for the slots it fills, by slot frame id.
        var fills: [String: [PenNode]]
    }

    /// Checks whether any descendant override keys lack a prop mapping.
    ///
    /// A key is mapped when *any* prop reads that node, so a descendant several props
    /// share is mapped like any other — the ambiguity between them is a `lint` finding,
    /// not a reason to inline the whole component. A slot frame's key is mapped when it
    /// writes the slot's content (`fills`) and nothing else, which the slot's prop carries.
    private static func hasUnmapped(
        overrides: [String: PenDescendantOverride],
        in component: ComponentDefinition,
        fills: [String: [PenNode]]
    ) -> Bool {
        let lookup = component.propsByNodeID
        for (nodeID, override) in overrides where lookup[nodeID] == nil {
            let fillsOnly = fills[nodeID] != nil && Set(override.properties.keys) == [PenNodePatcher.childrenKey]
            if !fillsOnly {
                return true
            }
        }
        return false
    }

    /// Emit a component reference tag with mapped props, and a prop per slot the instance
    /// fills: its content in a fragment, or `null` for an empty fill, which shows nothing
    /// where leaving the prop out shows the slot's default content.
    ///
    /// ```tsx
    /// <Screen
    ///   list={
    ///     <>
    ///       <ItemB />
    ///     </>
    ///   }
    /// />
    /// ```
    ///
    /// - Returns: The steps that draw the fills' content and close the tag; empty when the
    ///   instance fills no slot and the tag is written whole.
    private static func emitComponentRef(
        data: PenNode.RefData,
        call: ComponentCall,
        enclosing: ComponentDefinition,
        indent: Int,
        ctx: EmitContext
    ) -> [ReactEmitStep] {
        let pad = String(repeating: " ", count: indent)
        let componentName = call.name
        let component = call.component

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

        let filled = call.slots.filter { call.fills[$0.frame.id] != nil }
        if !filled.isEmpty {
            ctx.lines.append("\(pad)<\(componentName)")
            for attribute in propAttrs {
                ctx.lines.append("\(pad)  \(attribute)")
            }
            var steps: [ReactEmitStep] = []
            for slot in filled {
                steps += slotFillSteps(slot, content: call.fills[slot.frame.id] ?? [], enclosing: enclosing, indent: indent, ctx: ctx)
            }
            steps.append(.then {
                if !rootStyles.isEmpty {
                    ctx.lines.append("\(pad)  style={{")
                    for (key, value) in rootStyles {
                        ctx.lines.append("\(pad)    \(key): \(value),")
                    }
                    ctx.lines.append("\(pad)  }}")
                }
                ctx.lines.append("\(pad)/>")
            })
            return steps
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
        return []
    }

    /// Inline a component by cloning its source node and applying overrides; returns the
    /// steps that emit the tree and then report the inlining.
    private static func emitInlinedRef(
        _ node: PenNode,
        data: PenNode.RefData,
        component: ComponentDefinition,
        componentName: String,
        indent: Int,
        ctx: EmitContext
    ) -> [ReactEmitStep] {
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

        // Emit the patched node tree, then the diagnostic
        let severity: PenDiagnostic.Severity = ctx.options.strict ? .error : .warning
        let unmappedIDs = unmappedOverrideIDs(data.descendants, in: component)
        let message = "Inlined component '\(componentName)' due to unmapped descendant overrides: \(unmappedIDs.sorted().joined(separator: ", "))"
        return [
            .node(patched, component: dummyComp, indent: indent, isRoot: false, parentLayout: nil),
            .then {
                ctx.diagnostics?.add(PenDiagnostic(
                    severity: severity,
                    stage: .codeGen,
                    message: message,
                    nodeID: node.id
                ))
            },
        ]
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
