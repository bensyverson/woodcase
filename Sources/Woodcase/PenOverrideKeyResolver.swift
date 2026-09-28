//
//  PenOverrideKeyResolver.swift
//  Woodcase
//

import Foundation

/// Resolves the keys of an instance's `descendants` map the way Pen does.
///
/// A key is node ids joined by `/`. Pen reads it one step at a time, and which node a
/// step may name depends on who *wrote* that node — the component the instance
/// places, or a component nested inside it — measured with the `pen` CLI in
/// `project/2026-09-26-slot-override-keys.md`:
///
/// - The **first** step names any node the component itself wrote, however deep:
///   its own tree, and the content it writes into a nested instance's slot (a
///   `children` entry in that instance's `descendants`, or `children` written on the
///   nested `ref` itself), and into slots inside that.
///   A node another component wrote is never a first step.
/// - Each **later** step names a node placed below the previous one that was written
///   by a component the key has already entered, or — when the previous step is an
///   instance — a node of that instance's component's own tree, which enters it.
///   Content a nested component writes into *its* slots is therefore reached only
///   through the instance that holds it: `Mid/Place/Chip`, never `Mid/Chip`.
///
/// Pen keeps a resolved key in one canonical form, and so does ``Target``: the bare id
/// for a node the component wrote, and the path of instance ids for any other.
///
/// Content an instance writes into a slot *itself* is outside the rule: Pen does not
/// let an instance's own keys name it, so the walk leaves it out. The walk also reads
/// each nested `ref` as authored — an instance that repoints a nested ref, or a
/// component that is an alias of another, is followed only as far as the registry
/// chain goes — and a caller falls back to the key as written when this answers
/// nothing.
struct PenOverrideKeyResolver: Friendly {
    /// Where the node a key names sits.
    enum Site: Friendly {
        /// A node of the component's own tree: patched before the instance expands.
        case component

        /// A node the component wrote into a nested instance's slot: patched inside
        /// that slot's `children` before the nested instance expands.
        case slotContent

        /// A node another component wrote: handed, by its path, to the nested instance
        /// the path starts at, which applies it before its own nested refs expand.
        case nested
    }

    /// The node a key names, in Pen's canonical form.
    struct Target: Friendly {
        /// The key Pen keeps for the node: its id when the component wrote it, and
        /// otherwise the instance ids down to it, then its id.
        var canonicalKey: String

        /// Where the node sits.
        var site: Site
    }

    /// One node placed in the instance's expansion, in pre-order.
    struct Entry: Friendly {
        /// The node's own id.
        var id: String

        /// The instance ids down to the node, then its id — the id the expansion gives
        /// it, less the instance's own.
        var path: String

        /// The scope whose JSON wrote the node: 0 for the component itself.
        var writer: Int

        /// The scope whose expansion the node sits in: 0 for the component's own tree.
        var placement: Int

        /// For an instance, the scope its component's tree is placed in.
        var enters: Int?

        /// One past the index of the node's last descendant.
        var end: Int
    }

    /// The scope the component itself writes.
    static let componentScope = 0

    /// Every node of the instance's expansion, in pre-order.
    var entries: [Entry] = []

    /// Places a component's expansion so keys can be resolved against it.
    ///
    /// - Parameters:
    ///   - component: The component root the instance places, with its children.
    ///   - registry: Component id → component, for the instances nested inside it.
    init(component: PenNode, registry: [String: PenNode]) {
        var builder = Builder(registry: registry)
        builder.placeRoot(component)
        entries = builder.entries
    }

    /// The node a `descendants` key names, or `nil` when Pen would drop the key.
    ///
    /// - Parameter key: The key as written.
    /// - Returns: The node, in canonical form, or `nil`.
    func target(of key: String) -> Target? {
        let steps = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let first = steps.first, !steps.contains(where: \.isEmpty),
              var current = entries.firstIndex(where: { $0.id == first && $0.writer == Self.componentScope })
        else { return nil }

        var entered: Set<Int> = [Self.componentScope]
        for step in steps.dropFirst() {
            let parent = entries[current]
            guard let next = (current + 1 ..< parent.end).first(where: { index in
                let entry = entries[index]
                return entry.id == step && (entered.contains(entry.writer) || Self.isOwnTree(entry, of: parent))
            }) else { return nil }
            if Self.isOwnTree(entries[next], of: parent), let scope = parent.enters {
                entered.insert(scope)
            }
            current = next
        }
        return Self.target(entries[current])
    }

    /// Whether a node belongs to the own tree of the component an instance places.
    private static func isOwnTree(_ entry: Entry, of instance: Entry) -> Bool {
        guard let scope = instance.enters else { return false }
        return entry.writer == scope && entry.placement == scope
    }

    /// The canonical form of a placed node.
    private static func target(_ entry: Entry) -> Target {
        guard entry.writer == componentScope else {
            return Target(canonicalKey: entry.path, site: .nested)
        }
        return Target(
            canonicalKey: entry.id,
            site: entry.placement == componentScope ? .component : .slotContent
        )
    }
}
