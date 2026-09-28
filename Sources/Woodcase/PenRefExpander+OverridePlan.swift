//
//  PenRefExpander+OverridePlan.swift
//  Woodcase
//

import Foundation

extension PenRefExpander {
    /// One instance's descendant overrides, sorted by when the expansion applies them.
    ///
    /// Each key is resolved with ``PenOverrideKeyResolver`` — Pen's rule for which node
    /// a key names — and filed by where that node sits. A key the resolver cannot place
    /// is dropped, as Pen drops it, with two exceptions the resolver cannot judge: a
    /// bare key still patches the component's tree by id, and a path through a nested
    /// `ref` the instance itself repoints is handed to that ref — the resolver reads
    /// the ref as authored, so it cannot see the component the instance put there.
    ///
    /// Pen applies one override per node: when two keys name the same node, the one
    /// written last in the file applies, whole, and the other is dropped. Woodcase's
    /// model does not keep the order keys were written in, so the key that *sorts* last
    /// wins — the order Woodcase writes them in, so the two agree on any file Woodcase
    /// has saved. See `project/2026-09-26-slot-override-keys.md`.
    struct OverridePlan: Friendly {
        /// Overrides on the component's own tree, by node id: applied before expansion.
        var component: [String: PenDescendantOverride] = [:]

        /// Overrides on slot content the component wrote, by node id: applied inside
        /// the slot fills before the nested instances expand.
        var slotContent: [String: PenDescendantOverride] = [:]

        /// Overrides on nodes other components wrote, by canonical path: handed to the
        /// nested instance the path starts at.
        var nested: [String: PenDescendantOverride] = [:]

        /// Files an instance's overrides.
        ///
        /// - Parameters:
        ///   - overrides: The instance's `descendants` map.
        ///   - resolver: Builds the resolver for the instance's component; called at
        ///     most once, and only when there is a key to resolve.
        init(
            overrides: [String: PenDescendantOverride],
            resolver: () -> PenOverrideKeyResolver
        ) {
            guard !overrides.isEmpty else { return }
            let resolver = resolver()

            // Keyed by the node a key names, so a later key replaces an earlier one.
            var winners: [String: (key: String, target: PenOverrideKeyResolver.Target)] = [:]
            var unplaced: [String] = []
            for key in overrides.keys.sorted() {
                if let target = resolver.target(of: key) {
                    winners[target.canonicalKey] = (key, target)
                } else {
                    unplaced.append(key)
                }
            }

            for (key, target) in winners.values {
                file(overrides[key], under: target.canonicalKey, at: target.site)
            }
            for key in unplaced {
                let steps = key.split(separator: "/", maxSplits: 1).map(String.init)
                if steps.count == 1 {
                    component[key] = overrides[key]
                } else if overrides[steps[0]]?.properties[PenNodePatcher.refKey] != nil {
                    nested[key] = overrides[key]
                }
            }
        }

        /// Files one override under the key its site applies it by.
        private mutating func file(
            _ override: PenDescendantOverride?,
            under key: String,
            at site: PenOverrideKeyResolver.Site
        ) {
            switch site {
            case .component: component[key] = override
            case .slotContent: slotContent[key] = override
            case .nested: nested[key] = override
            }
        }
    }

    /// The resolvers built during one expansion, by the component id a `ref` names.
    ///
    /// Every instance of a component resolves its keys against the same placement, so
    /// it is built once per expansion rather than once per instance.
    final class ResolverCache {
        /// Component id → its resolver.
        private var resolvers: [String: PenOverrideKeyResolver] = [:]

        /// Creates an empty cache.
        init() {}

        /// The resolver for a component, built on first use.
        ///
        /// - Parameters:
        ///   - ref: The component id the instance's `ref` names.
        ///   - component: The component root the instance clones.
        ///   - registry: Component id → component.
        /// - Returns: The resolver.
        func resolver(
            for ref: String,
            component: PenNode,
            registry: [String: PenNode]
        ) -> PenOverrideKeyResolver {
            if let cached = resolvers[ref] { return cached }
            let built = PenOverrideKeyResolver(component: component, registry: registry)
            resolvers[ref] = built
            return built
        }
    }
}
