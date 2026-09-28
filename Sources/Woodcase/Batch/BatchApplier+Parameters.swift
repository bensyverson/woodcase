//
//  BatchApplier+Parameters.swift
//  Woodcase
//

import Foundation

/// Routing an override's keys through the parameters a component publishes.
///
/// A component declares its parameters in `common.metadata._props` — the same
/// declaration code generation has always read — and a published name is a key the
/// editing verbs accept: `override Card label=Hi` means the content of whatever node
/// `label` names. The redirect happens while the line is planned, so one `override`
/// may become writes to several nodes inside the instance, and every one of them is
/// judged, coerced and reported exactly as if it had been addressed the long way.
extension BatchApplier {
    /// One group of overrides bound for one node.
    struct OverrideGroup {
        /// The key inside the instance, or `nil` for the instance's root overrides.
        var descendantKey: String?

        /// The overrides for that node, keyed as the caller wrote them.
        var props: [String: AnyCodable]
    }

    /// An override's keys, sorted into the node each one lands on.
    struct RoutedOverrides {
        /// The key the caller addressed, or `nil` for the instance root.
        var targetKey: String?

        /// The keys that stay on the addressed node.
        var target: [String: AnyCodable]

        /// The keys a published parameter sent elsewhere, by descendant key.
        var redirected: [String: [String: AnyCodable]]

        /// What the routing has to say about itself.
        var notes: [WriteDivergence]

        /// The groups to write, the addressed node first.
        ///
        /// - Parameter keepingTarget: Whether the addressed node's group must be kept
        ///   even with no properties in it — which it must when the line also unsets a
        ///   key there.
        /// - Returns: One group per node, in a stable order.
        func groups(keepingTarget: Bool) -> [OverrideGroup] {
            var groups: [OverrideGroup] = []
            if !target.isEmpty || keepingTarget || redirected.isEmpty {
                groups.append(OverrideGroup(descendantKey: targetKey, props: target))
            }
            return groups + redirected
                .sorted { $0.key < $1.key }
                .map { OverrideGroup(descendantKey: $0.key, props: $0.value) }
        }
    }

    /// Sorts an override's keys into the nodes they land on.
    ///
    /// A key is routed only when the addressed node publishes it *and* the node's own
    /// property vocabulary does not already claim the name — the raw property wins, and
    /// a ``WriteDivergence`` says so rather than letting the caller guess which reading
    /// they got. A published name whose declared path resolves to nothing is refused
    /// here, before anything is written, naming both the parameter and the path.
    ///
    /// - Parameters:
    ///   - props: The overrides as the caller wrote them.
    ///   - descendantKey: The key the address resolved to, or `nil` for an instance root.
    ///   - definition: The node inside the component the address names, whose metadata
    ///     carries the declaration.
    ///   - document: The document, for resolving a declared path.
    /// - Returns: The keys grouped by the node they land on, and what to report.
    /// - Throws: ``BatchError/parameterPathNotFound(name:path:component:)``.
    static func routing(
        _ props: [String: AnyCodable],
        at descendantKey: String?,
        of definition: PenNode?,
        in document: EditableDocument
    ) throws -> RoutedOverrides {
        guard let definition else {
            return RoutedOverrides(
                targetKey: descendantKey, target: props, redirected: [:], notes: []
            )
        }
        let parameters = document.parameters(ofComponent: definition.id)
        guard !parameters.isEmpty else {
            return RoutedOverrides(
                targetKey: descendantKey, target: props, redirected: [:], notes: []
            )
        }
        let component = definition.common.name ?? definition.id
        var routed = RoutedOverrides(
            targetKey: descendantKey, target: [:], redirected: [:], notes: []
        )
        for key in props.keys.sorted() {
            let value = props[key] ?? .null
            guard let parameter = parameters.first(where: { $0.name == key }) else {
                routed.target[key] = value
                continue
            }
            guard !parameter.collidesWithProperty else {
                routed.target[key] = value
                routed.notes.append(shadowedParameter(parameter, on: component))
                continue
            }
            guard let nodeID = parameter.nodeID, let property = parameter.property else {
                throw BatchError.parameterPathNotFound(
                    name: parameter.name, path: parameter.path, component: component
                )
            }
            routed.redirected[
                overrideKey(forDescendant: nodeID, under: descendantKey), default: [:]
            ][property] = value
        }
        return routed
    }

    // MARK: - Private

    /// The `descendants` key a node inside a component takes, from where the caller
    /// was standing.
    ///
    /// The map keys a node by id, prefixed by the nested refs above it — the shape
    /// ``EditableDocument/resolve(_:tags:)-(String,_)`` produces. Routing a parameter
    /// from a node the caller reached through one of those refs keeps that prefix and
    /// swaps the last step, because the parameter's node is a sibling inside the same
    /// component.
    private static func overrideKey(forDescendant nodeID: String, under key: String?) -> String {
        let prefix = (key?.split(separator: NodeAddress.separator).map(String.init) ?? []).dropLast()
        return (prefix + [nodeID]).joined(separator: String(NodeAddress.separator))
    }

    /// What a published name the node's own vocabulary already claims has to say.
    ///
    /// Both readings are reasonable and only one can happen, so the write says which:
    /// the raw property, every time, with the address that reaches the parameter's node
    /// instead.
    private static func shadowedParameter(
        _ parameter: ComponentParameter,
        on component: String
    ) -> WriteDivergence {
        let address = parameter.address ?? parameter.path
        return WriteDivergence(
            kind: .shadowedParameter,
            severity: .note,
            target: parameter.name,
            requested: "an override of \(parameter.name)",
            applied: "the \(parameter.name) property of \(component)",
            note: "\(component) publishes \(parameter.name) as \(parameter.path) and has a "
                + "\(parameter.name) property of its own — the property wins, so write "
                + "\(address) to reach the parameter's node instead"
        )
    }
}
