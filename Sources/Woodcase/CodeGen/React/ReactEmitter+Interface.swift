//
//  ReactEmitter+Interface.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Interface

    static func emitInterface(_ component: ComponentDefinition, into lines: inout [String]) {
        lines.append("interface \(component.name)Props {")
        for prop in component.props {
            let tsType = typescriptType(for: prop.type)
            lines.append("  \(prop.name)?: \(tsType);")
        }
        // Role-derived props
        if let role = component.role {
            if role == .toggle {
                lines.append("  checked?: boolean;")
            }
            if role.knownStates.contains("disabled") {
                lines.append("  disabled?: boolean;")
            }
            if role == .link {
                lines.append("  href?: string;")
            }
        }
        // Structural state props
        let structuralStates = component.states.filter(\.isStructural)
        if component.role == .tabBar, !structuralStates.isEmpty {
            // N-way string union for tabBar selection
            let union = structuralStates.map { "\"\($0.name)\"" }.joined(separator: " | ")
            lines.append("  selected?: \(union);")
        } else {
            for state in structuralStates {
                lines.append("  \(state.name)?: boolean;")
            }
        }
        lines.append("  className?: string;")
        lines.append("  style?: React.CSSProperties;")
        lines.append("}")
    }

    // MARK: - Function

    static func emitFunction(
        _ component: ComponentDefinition,
        theme: ThemeManifest,
        ctx: EmitContext
    ) {
        let structuralStates = component.states.filter(\.isStructural)

        if structuralStates.isEmpty {
            emitSimpleFunction(component, theme: theme, ctx: ctx)
        } else if component.role == .tabBar {
            emitTabBarFunction(component, structuralStates: structuralStates, theme: theme, ctx: ctx)
        } else {
            emitStructuralFunction(component, structuralStates: structuralStates, theme: theme, ctx: ctx)
        }
    }

    // MARK: - Simple Function (no structural states)

    /// Emit a standard exported function — current behavior, unchanged.
    static func emitSimpleFunction(
        _ component: ComponentDefinition,
        theme _: ThemeManifest,
        ctx: EmitContext
    ) {
        ctx.lines.append("export function \(component.name)({")
        emitDestructuredProps(component, ctx: ctx)
        ctx.lines.append("}: \(component.name)Props) {")

        ctx.lines.append("  return (")
        emitNode(component.sourceNode, component: component, indent: 4, ctx: ctx)
        ctx.lines.append("  );")
        ctx.lines.append("}")
    }

    // MARK: - Structural Function

    /// Emit variant render functions + exported wrapper with conditional dispatch.
    static func emitStructuralFunction(
        _ component: ComponentDefinition,
        structuralStates: [StateDefinition],
        theme _: ThemeManifest,
        ctx: EmitContext
    ) {
        // 1. Emit default internal render function
        ctx.lines.append("function \(component.name)Default({")
        emitDestructuredProps(component, ctx: ctx)
        ctx.lines.append("}: \(component.name)Props) {")
        ctx.lines.append("  return (")
        emitNode(component.sourceNode, component: component, indent: 4, ctx: ctx)
        ctx.lines.append("  );")
        ctx.lines.append("}")
        ctx.lines.append("")

        // 2. Emit one internal render function per structural state
        for state in structuralStates {
            guard let variantNode = state.variantNode else { continue }
            let stateName = state.name.prefix(1).uppercased() + state.name.dropFirst()
            ctx.lines.append("function \(component.name)\(stateName)({")
            emitDestructuredProps(component, ctx: ctx)
            ctx.lines.append("}: \(component.name)Props) {")
            ctx.lines.append("  return (")

            // Clear state var substitution for variants — the variant's inline
            // values are already the correct state values, not base values.
            let savedAffected = ctx.stateAffectedProps
            ctx.stateAffectedProps = [:]

            let variantComponent = ComponentDefinition(
                id: component.id,
                name: component.name,
                sourceNode: variantNode,
                props: component.props,
                actions: component.actions,
                bindings: component.bindings,
                role: component.role,
                states: component.states
            )
            emitNode(variantNode, component: variantComponent, indent: 4, ctx: ctx)

            ctx.stateAffectedProps = savedAffected
            ctx.lines.append("  );")
            ctx.lines.append("}")
            ctx.lines.append("")
        }

        // 3. Emit exported wrapper with conditional dispatch
        ctx.lines.append("export function \(component.name)({")
        for state in structuralStates {
            ctx.lines.append("  \(state.name),")
        }
        ctx.lines.append("  ...props")
        ctx.lines.append("}: \(component.name)Props) {")

        // Build ternary chain
        var expr = "<\(component.name)Default {...props} />"
        for state in structuralStates.reversed() {
            let stateName = state.name.prefix(1).uppercased() + state.name.dropFirst()
            expr = "\(state.name) ? <\(component.name)\(stateName) {...props} /> : \(expr)"
        }
        ctx.lines.append("  return (")
        ctx.lines.append("    \(expr)")
        ctx.lines.append("  );")
        ctx.lines.append("}")
    }

    // MARK: - TabBar Function

    /// Emit N-way string dispatch for tabBar components.
    static func emitTabBarFunction(
        _ component: ComponentDefinition,
        structuralStates: [StateDefinition],
        theme _: ThemeManifest,
        ctx: EmitContext
    ) {
        // 1. Emit default internal render function
        ctx.lines.append("function \(component.name)Default({")
        emitDestructuredProps(component, ctx: ctx)
        ctx.lines.append("}: \(component.name)Props) {")
        ctx.lines.append("  return (")
        emitNode(component.sourceNode, component: component, indent: 4, ctx: ctx)
        ctx.lines.append("  );")
        ctx.lines.append("}")
        ctx.lines.append("")

        // 2. Emit one internal render function per state
        for state in structuralStates {
            guard let variantNode = state.variantNode else { continue }
            let stateName = state.name.prefix(1).uppercased() + state.name.dropFirst()
            ctx.lines.append("function \(component.name)\(stateName)({")
            emitDestructuredProps(component, ctx: ctx)
            ctx.lines.append("}: \(component.name)Props) {")
            ctx.lines.append("  return (")

            let savedAffected = ctx.stateAffectedProps
            ctx.stateAffectedProps = [:]

            let variantComponent = ComponentDefinition(
                id: component.id,
                name: component.name,
                sourceNode: variantNode,
                props: component.props,
                actions: component.actions,
                bindings: component.bindings,
                role: component.role,
                states: component.states
            )
            emitNode(variantNode, component: variantComponent, indent: 4, ctx: ctx)

            ctx.stateAffectedProps = savedAffected
            ctx.lines.append("  );")
            ctx.lines.append("}")
            ctx.lines.append("")
        }

        // 3. Emit exported wrapper with N-way selected dispatch
        ctx.lines.append("export function \(component.name)({")
        ctx.lines.append("  selected,")
        ctx.lines.append("  ...props")
        ctx.lines.append("}: \(component.name)Props) {")

        // Build chained ternary: selected === "home" ? <NavHome /> : selected === "log" ? <NavLog /> : <NavDefault />
        var expr = "<\(component.name)Default {...props} />"
        for state in structuralStates.reversed() {
            let stateName = state.name.prefix(1).uppercased() + state.name.dropFirst()
            expr = "selected === \"\(state.name)\" ? <\(component.name)\(stateName) {...props} /> :\n    \(expr)"
        }
        ctx.lines.append("  return (")
        ctx.lines.append("    \(expr)")
        ctx.lines.append("  );")
        ctx.lines.append("}")
    }

    // MARK: - Destructured Props Helper

    /// Emit the destructured props shared by all render function variants.
    private static func emitDestructuredProps(
        _ component: ComponentDefinition,
        ctx: EmitContext
    ) {
        for prop in component.props {
            let defaultStr = formatDefaultValue(prop)
            ctx.lines.append("  \(prop.name)\(defaultStr),")
        }
        if let role = component.role {
            if role == .toggle {
                ctx.lines.append("  checked = true,")
            }
            if role.knownStates.contains("disabled") {
                ctx.lines.append("  disabled,")
            }
            if role == .link {
                ctx.lines.append("  href,")
            }
        }
        ctx.lines.append("  className,")
        ctx.lines.append("  style,")
    }
}
