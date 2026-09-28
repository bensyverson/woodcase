//
//  PenNodePatcher+SlotContent.swift
//  Woodcase
//

import Foundation

public extension PenNodePatcher {
    /// Applies overrides to the nodes a component writes into its nested instances'
    /// slots.
    ///
    /// Slot content is not in the component's tree: it is a `children` value — in a
    /// `descendants` entry on a nested `ref`, or on the `ref` node itself, which fills
    /// its component's root — and it becomes nodes only when that ref expands. Pen lets
    /// the outer instance name such a node by its bare id, so the override is written
    /// into the slot content itself, before the nested ref expands — which is also what
    /// lets it change a nested `ref` the component wrote there.
    /// The walk follows slot content into the slots of the refs it holds in turn.
    ///
    /// - Parameters:
    ///   - node: The component tree, before its nested refs expand.
    ///   - overrides: Node id → override, for nodes written as slot content.
    /// - Returns: The tree with the slot content patched.
    static func applySlotContentOverrides(
        to node: PenNode,
        overrides: [String: PenDescendantOverride]
    ) -> PenNode {
        PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            guard case var .ref(data) = current.kind else { return .descend(current, ()) }
            data.descendants = data.descendants?.mapValues { entry in
                var patched = entry
                patched.properties = patchedSlotContent(of: entry.properties, overrides: overrides)
                return patched
            }
            data.rootOverrides = data.rootOverrides.map { patchedSlotContent(of: $0, overrides: overrides) }
            return .keep(PenNode(id: current.id, common: current.common, kind: .ref(data), extras: current.extras))
        } ?? node
    }

    /// Properties that may write slot content — a `descendants` entry, or a `ref`
    /// node's own root overrides — with that content patched, or unchanged when they
    /// write none.
    private static func patchedSlotContent(
        of properties: [String: AnyCodable],
        overrides: [String: PenDescendantOverride]
    ) -> [String: AnyCodable] {
        guard let value = properties[childrenKey],
              let children = decoded([PenNode].self, from: value)
        else { return properties }

        let patched = children.map { child in
            applySlotContentOverrides(to: applyOverrides(to: child, overrides: overrides), overrides: overrides)
        }
        guard patched != children,
              let encoded = try? JSONEncoder().encode(patched),
              let rewritten = try? JSONDecoder().decode(AnyCodable.self, from: encoded)
        else { return properties }
        var result = properties
        result[childrenKey] = rewritten
        return result
    }
}
