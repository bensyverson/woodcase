//
//  StateEmitter.swift
//  Woodcase
//

/// Converts pen-level state deltas into CSS for stateful components.
///
/// Produces a `states.css` file with CSS custom properties for designer-override
/// states and direct CSS properties spelling each ``StateEffect`` a smart-default state
/// carries. Follows the
/// `enum`-as-namespace pattern used by ``ThemeEmitter`` and ``ManifestEmitter``.
public enum StateEmitter {
    // MARK: - Public API

    /// Produce the full `states.css` content for all stateful components.
    ///
    /// Returns an empty string if no components have states.
    public static func emitCSS(
        for components: [ComponentDefinition],
        diagnostics: PenDiagnosticCollector? = nil
    ) -> String {
        var output = ""

        for component in components {
            guard !component.states.isEmpty else { continue }
            let css = emitComponentCSS(for: component, diagnostics: diagnostics)
            if !css.isEmpty {
                output += css
            }
        }

        return output
    }

    /// Convert a PascalCase component name to a kebab-case CSS class with `wc-` prefix.
    ///
    /// `ActionButton` → `wc-action-button`
    public static func cssClassName(for componentName: String) -> String {
        var result = "wc-"
        let chars = Array(componentName)
        for (i, char) in chars.enumerated() {
            if char.isUppercase {
                let prevIsUpper = i > 0 && chars[i - 1].isUppercase
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                // Insert dash before: first capital, or start of a new word
                // (transition from uppercase run to lowercase, e.g. "UI" → "T" in "UIToggle")
                if i > 0, !prevIsUpper || nextIsLower {
                    result += "-"
                }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }

    /// Returns `nodePath → {changed properties}` for designer overrides only.
    ///
    /// Smart defaults use additive CSS and don't need `var()` substitution.
    public static func stateAffectedProperties(
        for component: ComponentDefinition
    ) -> [String: Set<DeltaProperty>] {
        var result: [String: Set<DeltaProperty>] = [:]

        for state in component.states {
            guard state.source != .smartDefault, !state.isStructural else { continue }
            for delta in state.deltas {
                for change in delta.changes {
                    result[delta.nodePath, default: []].insert(change.property)
                }
            }
        }

        return result
    }

    /// Build a CSS variable name from class name, node path, and property.
    ///
    /// Root (`"."`): `--wc-action-button-bg`
    /// Non-root: `--wc-action-button-background-bg`
    public static func cssVarName(
        className: String,
        nodePath: String,
        property: DeltaProperty
    ) -> String {
        let suffix = cssSuffix(for: property)
        if nodePath == "." {
            return "--\(className)-\(suffix)"
        }
        // Use the last segment of the path, kebab-cased
        let segment = nodePath.split(separator: "/").last.map(String.init) ?? nodePath
        let kebab = segment.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }.joined(separator: "-")
        return "--\(className)-\(kebab)-\(suffix)"
    }

    // MARK: - Private

    /// CSS suffix for each DeltaProperty.
    private static func cssSuffix(for property: DeltaProperty) -> String {
        switch property {
        case .fills: "bg"
        case .textColor: "color"
        case .cornerRadius: "radius"
        case .opacity: "opacity"
        case .fontSize: "font-size"
        case .fontWeight: "font-weight"
        case .width: "width"
        case .height: "height"
        case .padding: "padding"
        case .gap: "gap"
        case .strokeColor: "border-color"
        case .shadow: "shadow"
        case .blur: "filter"
        case .strokeWidth: "border-width"
        case .transform: "transform"
        }
    }

    /// DeltaProperty → CSS property name for designer overrides.
    private static func cssProperty(for property: DeltaProperty) -> String {
        switch property {
        case .fills: "background-color"
        case .textColor: "color"
        case .cornerRadius: "border-radius"
        case .opacity: "opacity"
        case .fontSize: "font-size"
        case .fontWeight: "font-weight"
        case .width: "width"
        case .height: "height"
        case .padding: "padding"
        case .gap: "gap"
        case .strokeColor: "border-color"
        case .shadow: "box-shadow"
        case .blur: "filter"
        case .strokeWidth: "border-width"
        case .transform: "transform"
        }
    }

    /// The CSS selector for a state trigger on a component's class.
    ///
    /// Focus is `:focus-visible`, except on a text input or a select: their root is a
    /// wrapper `<div>` and the focus lands on the control inside it, so it is
    /// `:focus-within`. A pressed component is `:active`; an attribute is a `data-*` match.
    static func selector(for trigger: StateTrigger, role: ComponentRole?, className: String) -> String {
        switch trigger {
        case .hover:
            ".\(className):hover"
        case .pressed:
            ".\(className):active"
        case .disabled:
            ".\(className):disabled"
        case .focused:
            role == .textInput || role == .select
                ? ".\(className):focus-within"
                : ".\(className):focus-visible"
        case let .attribute(name, value):
            ".\(className)[data-\(name)=\"\(value)\"]"
        }
    }

    /// Check if the component's root node has transforms that would conflict with
    /// smart-default transform properties.
    private static func rootHasTransform(_ component: ComponentDefinition) -> Bool {
        DeltaTransform(of: component.sourceNode.common).cssFunctions != nil
    }

    /// Resolve the base value of a property from the component's source node tree.
    private static func resolveBaseValue(
        _ property: DeltaProperty,
        at nodePath: String,
        in component: ComponentDefinition
    ) -> String? {
        let node = resolveNode(at: nodePath, in: component.sourceNode)
        guard let node else { return nil }

        switch property {
        case .fills:
            return extractFirstFillColor(from: node)
        case .textColor:
            // The colour the text is emitted with at rest, by the same rule.
            if case let .text(data) = node.kind {
                return ReactEmitter.glyphColor(data.fills)
            }
            return nil
        case .opacity:
            return node.common.opacity?.literalValue.map { String($0) }
        case .cornerRadius:
            return extractCornerRadius(from: node)
        case .transform:
            return DeltaTransform(of: node.common).cssValue
        default:
            return nil
        }
    }

    /// Walk the node tree to find a node at the given path.
    private static func resolveNode(
        at path: String,
        in root: PenNode
    ) -> PenNode? {
        guard path != "." else { return root }

        let segments = path.split(separator: "/").map(String.init)
        var current = root

        for segment in segments {
            let children: [PenNode]? = switch current.kind {
            case let .frame(data): data.children
            case let .group(data): data.children
            default: nil
            }
            guard let child = children?.first(where: { $0.common.name == segment }) else {
                return nil
            }
            current = child
        }

        return current
    }

    /// Extract the first fill's color string from a node.
    private static func extractFirstFillColor(from node: PenNode) -> String? {
        let fills: PenFills? = switch node.kind {
        case let .frame(data): data.fills
        case let .rectangle(data): data.fills
        case let .ellipse(data): data.fills
        default: nil
        }
        return fills?.all.first.flatMap { fillColorValue($0) }
    }

    /// Extract a color string from a PenFill, converting variable references to CSS.
    private static func fillColorValue(_ fill: PenFill) -> String? {
        switch fill {
        case let .shorthand(hex): cssValue(hex)
        case let .color(c): c.color.literalValue.map { cssValue($0) }
        default: nil
        }
    }

    /// Convert a pen value string to CSS, resolving `$name` variable references to `var(--name)`.
    private static func cssValue(_ value: String) -> String {
        if value.hasPrefix("$") {
            return "var(--\(value.dropFirst()))"
        }
        return value
    }

    /// Extract corner radius as a CSS value string.
    private static func extractCornerRadius(from node: PenNode) -> String? {
        guard case let .frame(data) = node.kind, let cr = data.cornerRadius else {
            return nil
        }
        switch cr {
        case let .uniform(value):
            return value.literalValue.map { "\(Int($0))px" }
        case .perCorner:
            return nil // Too complex for var() substitution
        }
    }

    /// Format a delta value as a CSS value string.
    private static func formatDeltaValue(
        _ value: DeltaValue,
        property: DeltaProperty
    ) -> String {
        switch value {
        case let .encoded(encoded):
            formatEncodedValue(encoded, property: property)
        case let .transform(transform):
            transform.cssValue
        }
    }

    /// Format the diff's pen-level encoding of a value as a CSS value string.
    private static func formatEncodedValue(
        _ value: AnyCodable,
        property: DeltaProperty
    ) -> String {
        switch value {
        case let .string(s):
            return cssValue(s)
        case let .int(n):
            let needsPx = [.cornerRadius, .fontSize, .width, .height, .padding, .gap, .strokeWidth].contains(property)
            return needsPx ? "\(n)px" : "\(n)"
        case let .double(d):
            let needsPx = [.cornerRadius, .fontSize, .width, .height, .padding, .gap, .strokeWidth].contains(property)
            let formatted = d == d.rounded() && !d.isInfinite ? "\(Int(d))" : "\(d)"
            return needsPx ? "\(formatted)px" : formatted
        default:
            return String(describing: value)
        }
    }

    /// Emit CSS for a single component.
    private static func emitComponentCSS(
        for component: ComponentDefinition,
        diagnostics: PenDiagnosticCollector?
    ) -> String {
        let className = cssClassName(for: component.name)
        let hasTransform = rootHasTransform(component)

        var output = ""

        let overrideStates = component.states.filter { $0.source != .smartDefault && !$0.isStructural }

        // --- Designer overrides: CSS custom properties ---
        if !overrideStates.isEmpty {
            // Collect all affected properties and their base values for the base rule
            var baseProps: [(varName: String, value: String)] = []
            var stateRules: [(selector: String, props: [(varName: String, value: String)])] = []

            for state in overrideStates {
                var stateProps: [(varName: String, value: String)] = []

                for delta in state.deltas {
                    for change in delta.changes {
                        let varName = cssVarName(
                            className: className,
                            nodePath: delta.nodePath,
                            property: change.property
                        )
                        let stateValue = formatDeltaValue(change.value, property: change.property)
                        stateProps.append((varName, stateValue))

                        // Collect base value (only if not already added)
                        if !baseProps.contains(where: { $0.varName == varName }) {
                            let baseValue = resolveBaseValue(
                                change.property, at: delta.nodePath, in: component
                            ) ?? stateValue
                            baseProps.append((varName, baseValue))
                        }
                    }
                }

                if !stateProps.isEmpty {
                    let sel = selector(for: state.trigger, role: component.role, className: className)
                    stateRules.append((sel, stateProps))
                }
            }

            // Emit base rule
            if !baseProps.isEmpty {
                output += ".\(className) {\n"
                for (varName, value) in baseProps.sorted(by: { $0.varName < $1.varName }) {
                    output += "  \(varName): \(value);\n"
                }
                output += "}\n"
            }

            // Emit state rules
            for (sel, props) in stateRules {
                output += "\(sel) {\n"
                for (varName, value) in props.sorted(by: { $0.varName < $1.varName }) {
                    output += "  \(varName): \(value);\n"
                }
                output += "}\n"
            }
        }

        // --- Effects (smart defaults): direct CSS properties ---
        for state in component.states where !state.effects.isEmpty {
            let props = effectCSS(
                for: state,
                hasTransform: hasTransform,
                diagnostics: diagnostics,
                componentName: component.name
            )
            guard !props.isEmpty else { continue }

            let sel = selector(for: state.trigger, role: component.role, className: className)
            output += "\(sel) {\n"
            for (prop, value) in props {
                output += "  \(prop): \(value);\n"
            }
            output += "}\n"
        }

        return output
    }

    /// The CSS declarations spelling a state's ``StateEffect``s, in order.
    ///
    /// A scale is left out, with a warning, when the root is rotated or flipped: its
    /// `transform` would replace the one that draws the rotation.
    private static func effectCSS(
        for state: StateDefinition,
        hasTransform: Bool,
        diagnostics: PenDiagnosticCollector?,
        componentName: String
    ) -> [(property: String, value: String)] {
        state.effects.flatMap { effect -> [(property: String, value: String)] in
            if case .scale = effect, hasTransform {
                let declaration = effect.cssDeclarations.map { "\($0.property): \($0.value)" }
                    .joined(separator: "; ")
                diagnostics?.warn(
                    "Skipping transform smart default for '\(componentName)' \(state.name) state: "
                        + "base node has rotation/flip that would conflict with \(declaration)",
                    stage: .codeGen,
                    nodeID: nil
                )
                return []
            }
            return effect.cssDeclarations
        }
    }
}
