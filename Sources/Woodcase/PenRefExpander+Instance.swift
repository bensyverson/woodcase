//
//  PenRefExpander+Instance.swift
//  Woodcase
//

import Foundation

extension PenRefExpander {
    /// An instance cloned and patched, ready for its nested refs to expand.
    struct PreparedInstance: Friendly {
        /// The component clone, overrides on nodes the component wrote applied, ids
        /// prefixed with the instance's.
        var node: PenNode

        /// The component ids on this expansion chain, the instance's own included.
        var chainVisited: Set<String>
    }

    /// Clones the component an instance places and applies everything that must land
    /// before its nested refs expand.
    ///
    /// - Parameters:
    ///   - refNode: The `ref` node.
    ///   - refData: Its payload.
    ///   - registry: Component id → component.
    ///   - visited: The component ids already on this expansion chain.
    ///   - cache: The override-key resolvers built so far in this expansion.
    /// - Returns: The prepared clone, or `nil` for a circular or unresolved ref, which
    ///   stays as written.
    static func prepareInstance(
        refNode: PenNode,
        refData: PenNode.RefData,
        registry: [String: PenNode],
        visited: Set<String>,
        cache: ResolverCache
    ) -> PreparedInstance? {
        guard !visited.contains(refData.ref),
              let resolved = resolveChain(of: refData.ref, registry: registry, visited: visited)
        else { return nil }
        let (component, chainVisited) = resolved

        var expanded = component
        let rootOverrides = refData.rootOverrides ?? [:]
        if !rootOverrides.isEmpty {
            expanded = PenNodePatcher.patchNode(expanded, with: rootOverrides)
        }

        // Overrides on nodes the component wrote apply before expansion, by their
        // original ids — slot content included, inside the fill that writes it. Those
        // on nodes other components wrote are handed to the nested instance their path
        // starts at, which applies them as its own.
        let plan = OverridePlan(overrides: refData.descendants ?? [:]) {
            cache.resolver(for: refData.ref, component: component, registry: registry)
        }
        if !plan.component.isEmpty {
            // Children the instance writes on its own `ref` node are its own slot
            // content, which Pen does not let its keys reach.
            expanded = PenNodePatcher.applyOverrides(
                to: expanded, overrides: plan.component,
                enteringRoot: rootOverrides[PenNodePatcher.childrenKey] == nil
            )
        }
        if !plan.slotContent.isEmpty {
            expanded = PenNodePatcher.applySlotContentOverrides(to: expanded, overrides: plan.slotContent)
        }
        if !plan.nested.isEmpty {
            expanded = handDown(plan.nested, into: expanded)
        }

        expanded = prefixIDs(in: expanded, prefix: refNode.id)
        expanded.common = transferCommonProperties(from: refNode.common, to: expanded.common)
        return PreparedInstance(node: expanded, chainVisited: chainVisited)
    }

    /// The component a `ref` names, following alias chains, with every link's
    /// overrides applied.
    ///
    /// A reusable component may itself be a `ref` to another ("Icon Button/Secondary"
    /// is a ref to "Button/Secondary" with overrides). The walk reaches the end of the
    /// chain first, then applies each link's overrides to the node it ends in,
    /// innermost link first so an outer link's override wins. Patching link by link as
    /// the walk goes would put an outer link's descendant overrides on the next link —
    /// a ref with no children — where they are silently lost.
    ///
    /// - Parameters:
    ///   - ref: The component id the instance names.
    ///   - registry: Component id → component.
    ///   - visited: The component ids already on this expansion chain.
    /// - Returns: The resolved component and the chain's visited ids, or `nil` when the
    ///   registry holds no such component.
    static func resolveChain(
        of ref: String,
        registry: [String: PenNode],
        visited: Set<String>
    ) -> (PenNode, Set<String>)? {
        guard var component = registry[ref] else { return nil }

        var chainVisited = visited
        chainVisited.insert(ref)
        var links: [PenNode] = []
        while case let .ref(innerRef) = component.kind {
            guard !chainVisited.contains(innerRef.ref),
                  let next = registry[innerRef.ref]
            else { break }
            links.append(component)
            chainVisited.insert(innerRef.ref)
            component = next
        }
        for link in links.reversed() {
            guard case let .ref(linkRef) = link.kind else { continue }
            if let rootOverrides = linkRef.rootOverrides, !rootOverrides.isEmpty {
                component = PenNodePatcher.patchNode(component, with: rootOverrides)
            }
            if let overrides = linkRef.descendants {
                component = PenNodePatcher.applyOverrides(to: component, overrides: overrides)
            }
            component.common = transferCommonProperties(from: link.common, to: component.common)
        }
        return (component, chainVisited)
    }

    /// Hands overrides on nodes other components wrote to the nested instances that
    /// hold them.
    ///
    /// Such a key is a path whose first step is an instance in the component's tree —
    /// Pen's canonical form for it is the instance ids down to the node. `Mid/Dot`
    /// becomes `Dot` in `Mid`'s own `descendants`, so it applies when `Mid` expands,
    /// before `Dot` does: an override on a nested *instance* patches its `ref` node,
    /// exactly as the instance's own key would, and slot content it writes is expanded
    /// and prefixed with everything else. Where `Mid` already overrides the same key,
    /// the outer override's properties win and the inner one's others stay. A key whose
    /// first step is no `ref` in the tree names nothing the expansion holds, and is
    /// dropped — as Pen drops every key it cannot place.
    ///
    /// - Parameters:
    ///   - overrides: Path → override, as ``OverridePlan/nested`` files them.
    ///   - node: The instance's clone, before its ids are prefixed.
    /// - Returns: The clone with the overrides written into its nested `ref` nodes.
    static func handDown(
        _ overrides: [String: PenDescendantOverride],
        into node: PenNode
    ) -> PenNode {
        var byInstance: [String: [String: PenDescendantOverride]] = [:]
        for (key, override) in overrides {
            let steps = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard steps.count == 2 else { continue }
            byInstance[steps[0], default: [:]][steps[1]] = override
        }
        var pending = byInstance
        return PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            guard !pending.isEmpty else { return .keep(current) }
            guard case var .ref(data) = current.kind,
                  let handed = pending.removeValue(forKey: current.id)
            else { return .descend(current, ()) }
            var descendants = data.descendants ?? [:]
            for (key, outer) in handed {
                descendants[key] = merging(outer, over: descendants[key])
            }
            data.descendants = descendants
            return .keep(PenNode(id: current.id, common: current.common, kind: .ref(data), extras: current.extras))
        } ?? node
    }

    /// An outer instance's override laid over a nested instance's own for the same key.
    private static func merging(
        _ outer: PenDescendantOverride,
        over inner: PenDescendantOverride?
    ) -> PenDescendantOverride {
        guard let inner, !outer.isObjectReplacement else { return outer }
        return PenDescendantOverride(properties: inner.properties.merging(outer.properties) { _, new in new })
    }
}
