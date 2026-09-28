//
//  ComponentAnalyzer.swift
//  Woodcase
//

import Foundation

/// Analyzes a .pen document to extract reusable component definitions for code generation.
///
/// Walks the node tree looking for `reusable: true` nodes, then extracts props,
/// actions, and bindings from their metadata and descendants. Each component's name is
/// unique, ignoring case: two whose frame names make the same type are numbered from 2 in
/// document order.
public enum ComponentAnalyzer {
    /// Analyze a document and produce component definitions.
    public static func analyze(_ document: PenDocument) -> [ComponentDefinition] {
        // Pass 1: Collect reusable components + their sibling scope
        var results: [ComponentDefinition] = []
        var siblingScope: [String: [PenNode]] = [:]
        collectComponents(from: document.children, into: &results, siblingScope: &siblingScope)

        // Build lookup structures for state discovery
        let allNodes = flattenNodes(document.children)
        let nodeByID = Dictionary(allNodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let topLevelNonReusable = document.children.filter { $0.common.reusable != true }
        let reusableNames = Set(results.map(\.name))

        // Pass 2-4: Resolve roles, discover variants, fill smart defaults
        for i in results.indices {
            // Pass 2: Resolve role from root _role metadata
            if let metadata = results[i].sourceNode.common.metadata,
               case let .string(roleString) = metadata["_role"]
            {
                results[i].role = ComponentRole(rawValue: roleString)
            }

            // Pass 3: Scan for state variants
            let rawName = results[i].sourceNode.common.name ?? results[i].id
            let componentBaseName = rawName.hasSuffix("/") ? rawName : rawName
            var states: [StateDefinition] = []
            var coveredStateNames: Set<String> = []

            // 3a: _states metadata (highest priority)
            if let metadata = results[i].sourceNode.common.metadata,
               case let .dictionary(statesDict) = metadata["_states"]
            {
                for (stateName, nodeIDValue) in statesDict {
                    guard case let .string(nodeID) = nodeIDValue,
                          let variantNode = nodeByID[nodeID]
                    else { continue }

                    let lowerState = stateName.lowercased()
                    let trigger = results[i].role.flatMap { RoleStateMapping.trigger(for: $0, state: lowerState) }
                        ?? .attribute(name: lowerState, value: "true")

                    let diffResult = NodeDiffer.diff(base: results[i].sourceNode, variant: variantNode)
                    states.append(StateDefinition(
                        name: lowerState,
                        trigger: trigger,
                        source: .designerOverride,
                        isStructural: diffResult.isStructural,
                        deltas: diffResult.deltas,
                        variantNode: variantNode
                    ))
                    coveredStateNames.insert(lowerState)
                }
            }

            // 3b: {Name}:{state} naming convention
            let isTabBar = results[i].role == .tabBar
            // For tabBar, scan all siblings at the same hierarchy level;
            // for other roles, scan only non-reusable top-level nodes.
            let scanSiblings: [PenNode] = if isTabBar {
                (siblingScope[results[i].id] ?? document.children)
                    .filter { $0.id != results[i].id }
            } else {
                topLevelNonReusable
            }
            var discoveredVariantIDs: [String: String] = [:]

            for sibling in scanSiblings {
                guard let siblingName = sibling.common.name else { continue }
                guard let colonIndex = siblingName.lastIndex(of: ":") else { continue }

                let prefix = String(siblingName[siblingName.startIndex ..< colonIndex])
                let stateSuffix = String(siblingName[siblingName.index(after: colonIndex)...])
                let lowerState = stateSuffix.lowercased()

                // Match against the component's raw name
                guard prefix == componentBaseName else { continue }

                // Skip if this variant name is itself reusable (unless tabBar)
                let sanitizedVariantName = CodeGenName.typeName(siblingName)
                if reusableNames.contains(sanitizedVariantName) {
                    guard isTabBar else { continue }
                }

                // Skip if already covered by _states metadata
                guard !coveredStateNames.contains(lowerState) else { continue }

                if isTabBar {
                    // TabBar states are purely structural — no pseudo-class or data-attribute triggers
                    let diffResult = NodeDiffer.diff(base: results[i].sourceNode, variant: sibling)
                    states.append(StateDefinition(
                        name: lowerState,
                        trigger: .attribute(name: lowerState, value: "true"),
                        source: .designerOverride,
                        isStructural: true,
                        deltas: diffResult.deltas,
                        variantNode: sibling
                    ))
                    discoveredVariantIDs[lowerState] = sibling.id
                } else {
                    // Need a trigger — from role mapping, or generic data attribute
                    let trigger: StateTrigger
                    if let role = results[i].role,
                       let roleTrigger = RoleStateMapping.trigger(for: role, state: lowerState)
                    {
                        trigger = roleTrigger
                    } else if results[i].role != nil {
                        // Known role but unknown state name — use data attribute
                        trigger = .attribute(name: lowerState, value: "true")
                    } else {
                        // No role and no trigger mapping — skip unknown state on role-less component
                        continue
                    }

                    let diffResult = NodeDiffer.diff(base: results[i].sourceNode, variant: sibling)
                    states.append(StateDefinition(
                        name: lowerState,
                        trigger: trigger,
                        source: .designerOverride,
                        isStructural: diffResult.isStructural,
                        deltas: diffResult.deltas,
                        variantNode: sibling
                    ))
                }
                coveredStateNames.insert(lowerState)
            }

            if isTabBar {
                results[i].variantIDs = discoveredVariantIDs
            }

            // Pass 4: Fill smart defaults for uncovered states
            if let role = results[i].role {
                let defaults = RoleStateMapping.smartDefaults(for: role)
                for defaultState in defaults where !coveredStateNames.contains(defaultState.name) {
                    states.append(defaultState)
                }
            }

            results[i].states = states
        }

        // Pass 5: Exclude components whose IDs were claimed as tabBar variants
        let claimedVariantIDs: Set<String> = Set(results.flatMap(\.variantIDs.values))
        results = results.filter { !claimedVariantIDs.contains($0.id) }

        return disambiguated(results).sorted { $0.name < $1.name }
    }

    /// `components`, in document order, renamed where a name is reserved
    /// (``CodeGenName/reservedNames``: `Text` is `TextComponent`), by a `Component` suffix,
    /// and where it is one an earlier component already has — compared without case, since
    /// each component's file shares one folder on a case-insensitive disk — by a number
    /// from 2. Every emitter, the manifest and the viewer read the name from here, so they
    /// agree; ``PageAnalyzer`` does the same for pages.
    private static func disambiguated(_ components: [ComponentDefinition]) -> [ComponentDefinition] {
        var taken: Set<String> = []
        return components.map { component in
            var renamed = component
            let base = CodeGenName.reservedNames.contains(component.name)
                ? component.name + CodeGenName.reservedComponentSuffix
                : component.name
            renamed.name = CodeGenName.numbered(base) { taken.contains($0.lowercased()) }
            taken.insert(renamed.name.lowercased())
            return renamed
        }
    }

    /// Recursively flatten all nodes in the tree for ID-based lookup.
    private static func flattenNodes(_ nodes: [PenNode]) -> [PenNode] {
        var result: [PenNode] = []
        for node in nodes {
            result.append(node)
            result.append(contentsOf: flattenNodes(children(of: node)))
        }
        return result
    }

    // MARK: - Component Collection

    private static func collectComponents(
        from nodes: [PenNode],
        into results: inout [ComponentDefinition],
        siblingScope: inout [String: [PenNode]]
    ) {
        for node in nodes {
            if node.common.reusable == true {
                let definition = buildDefinition(for: node)
                results.append(definition)
                siblingScope[definition.id] = nodes
            }
            let nodeChildren = children(of: node)
            if !nodeChildren.isEmpty {
                collectComponents(from: nodeChildren, into: &results, siblingScope: &siblingScope)
            }
        }
    }

    private static func buildDefinition(for node: PenNode) -> ComponentDefinition {
        let name = CodeGenName.typeName(node.common.name ?? node.id)
        let props = extractProps(from: node)
        var actions: [ActionDefinition] = []
        var bindings: [BindingDefinition] = []

        // Check the root node itself for _role
        extractInteractiveMetadata(from: node, actions: &actions, bindings: &bindings)

        // Walk descendants for _role and _action
        walkDescendants(of: node, actions: &actions, bindings: &bindings)

        return ComponentDefinition(
            id: node.id,
            name: name,
            sourceNode: node,
            props: props,
            actions: actions,
            bindings: bindings
        )
    }

    // MARK: - Props

    private static func extractProps(from node: PenNode) -> [PropDefinition] {
        guard let metadata = node.common.metadata,
              case let .dictionary(propsDict) = metadata["_props"]
        else {
            return []
        }

        var props: [PropDefinition] = []
        for (propName, pathValue) in propsDict {
            guard case let .string(path) = pathValue else { continue }
            let targetNode = resolveDescendantPath(path, from: node)
            let (propType, defaultValue) = inferPropType(from: targetNode)
            props.append(PropDefinition(
                name: propName,
                path: path,
                type: propType,
                defaultValue: defaultValue,
                targetNodeID: targetNode?.id
            ))
        }
        return props.sorted { $0.name < $1.name }
    }

    // MARK: - Prop Type Inference

    /// The type a declared parameter has, and the value the component gives it today.
    ///
    /// Internal rather than private because ``ComponentParameter`` is the same reading
    /// for the editing verbs: `get` prints the type codegen will emit, and it has to be
    /// *this* answer rather than a second one that drifts.
    ///
    /// - Parameter node: The descendant a `_props` entry names, or `nil` when the path
    ///   resolves to nothing.
    /// - Returns: The inferred type and the target's current value, where it has one.
    static func inferPropType(from node: PenNode?) -> (type: PropType, defaultValue: AnyCodable?) {
        guard let node else { return (.string, nil) }

        switch node.kind {
        case let .text(data):
            let defaultValue = extractTextDefault(from: data)
            return (.string, defaultValue)

        case let .rectangle(data):
            return inferFromFills(data.fills)

        case let .frame(data):
            return inferFromFills(data.fills)

        case let .ellipse(data):
            return inferFromFills(data.fills)

        default:
            return (.string, nil)
        }
    }

    private static func inferFromFills(_ fills: PenFills?) -> (PropType, AnyCodable?) {
        guard let fills else { return (.string, nil) }
        for fill in fills.all {
            switch fill {
            case let .image(imageFill):
                guard let url = imageFill.url else { continue }
                return (.imageURL, .string(url))
            case let .shorthand(colorString):
                return (.color, .string(colorString))
            case let .color(colorFill):
                if let literal = colorFill.color.literalValue {
                    return (.color, .string(literal))
                }
                if let varName = colorFill.color.variableName {
                    return (.color, .string("$\(varName)"))
                }
                return (.color, nil)
            default:
                continue
            }
        }
        return (.string, nil)
    }

    private static func extractTextDefault(from data: PenNode.TextData) -> AnyCodable? {
        guard let literal = data.content?.literalValue else { return nil }
        return .string(literal)
    }

    // MARK: - Actions & Bindings

    private static func walkDescendants(
        of node: PenNode,
        actions: inout [ActionDefinition],
        bindings: inout [BindingDefinition]
    ) {
        for child in children(of: node) {
            extractInteractiveMetadata(from: child, actions: &actions, bindings: &bindings)
            walkDescendants(of: child, actions: &actions, bindings: &bindings)
        }
    }

    private static func extractInteractiveMetadata(
        from node: PenNode,
        actions: inout [ActionDefinition],
        bindings: inout [BindingDefinition]
    ) {
        guard let metadata = node.common.metadata,
              case let .string(role) = metadata["_role"]
        else {
            return
        }

        // Check for explicit _action
        if case let .string(actionName) = metadata["_action"] {
            actions.append(ActionDefinition(name: actionName, role: role, nodeID: node.id))
        } else if let defaultAction = defaultAction(for: role) {
            actions.append(ActionDefinition(name: defaultAction, role: role, nodeID: node.id))
        }

        // Check for binding roles
        if isBindingRole(role) {
            let bindingName = camelCase(node.common.name ?? node.id)
            let valueType = bindingValueType(for: role)
            bindings.append(BindingDefinition(
                name: bindingName,
                role: role,
                nodeID: node.id,
                valueType: valueType
            ))
        }
    }

    /// Returns the default action name for interactive roles.
    private static func defaultAction(for role: String) -> String? {
        switch role {
        case "button": "click"
        case "link": "click"
        default: nil
        }
    }

    /// Whether the role implies a two-way data binding.
    private static func isBindingRole(_ role: String) -> Bool {
        switch role {
        case "textInput", "toggle", "select": true
        default: false
        }
    }

    /// The default value type for a binding role.
    private static func bindingValueType(for role: String) -> PropType {
        switch role {
        case "toggle": .boolean
        default: .string
        }
    }

    /// Convert a name like "My Field" to "myField".
    private static func camelCase(_ name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return name.lowercased() }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return first.lowercased() + rest.joined()
    }

    // MARK: - Children

    /// A node's inline children.
    ///
    /// The rule itself lives on ``ComponentAnalyzer/childNodes(of:)``
    /// (`ComponentAnalyzer+DescendantPath.swift`), which `codegen-prop-path` walks with
    /// too; this is the name the analyzer's own passes call it by.
    private static func children(of node: PenNode) -> [PenNode] {
        childNodes(of: node)
    }
}
