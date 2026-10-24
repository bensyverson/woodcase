//
//  SlotMap.swift
//  Woodcase
//

import Foundation

/// Every slot one instance shows, and every node of it, by the key the instance names it
/// by.
///
/// Built by ``EditableDocument/slotMap(of:)`` from the instance as the expansion prepares
/// it, so what it holds is what is drawn: a slot's content is its fill when the instance
/// wrote one, else its component's default content with the instance's overrides folded
/// in. Keys are relative to the outermost instance (`Row1`, `PScr/List`, `Nest/NRow1`);
/// a node's expanded id is the instance's id, a `/`, then its key — and, for an instance
/// root, its component root's id after that.
struct SlotMap {
    /// One slot of the instance.
    struct Site {
        /// The slot frame's key.
        var slotKey: String

        /// Where its fill is stored.
        var location: SlotFillLocation

        /// The slot frame as prepared for expansion: its children are what the slot shows,
        /// its ids prefixed.
        var frame: PenNode

        /// The component whose tree holds the slot frame.
        var componentID: String

        /// The slot frame's id in that component.
        var componentSlotID: String

        /// The expanded id of the instance root that shows the slot.
        var instanceRootID: String

        /// The key prefix of the slot's content: the key of the instance whose component
        /// holds the slot, and a `/`; empty for the outermost instance's own slots.
        var contentPrefix: String

        /// Whether the instance wrote a fill for the slot.
        var isFilled: Bool

        /// The keys of the slot's top-level content, in order.
        var contentKeys: [String] = []
    }

    /// One node the instance shows.
    struct Node {
        /// The node as prepared for expansion, its id the expanded path.
        var node: PenNode

        /// The key of the node it sits in, or `nil` for the instance's root.
        var parentKey: String?

        /// The index of the slot whose content holds it, or `nil` for a node of a
        /// component.
        var siteIndex: Int?

        /// Its id in the fill or component that wrote it: its key's last step.
        var localID: String

        /// The component root it places, for an instance; `nil` for any other node.
        var componentRootID: String?
    }

    /// The outermost instance's stored `ref` node id.
    var refID: String

    /// The slots, in tree order.
    var sites: [Site] = []

    /// Every node, by key.
    var nodes: [String: Node] = [:]

    /// The site whose slot frame has this key.
    func site(slotKey: String) -> Int? {
        sites.firstIndex { $0.slotKey == slotKey }
    }

    /// The expanded id of the node a key names: the instance's id and the key, and for an
    /// instance its component root's id after that.
    func expandedID(of key: String) -> String {
        let path = refID + String(NodeAddress.separator) + key
        guard let root = nodes[key]?.componentRootID else { return path }
        return path + String(NodeAddress.separator) + root
    }

    /// The key an expanded id names, or `nil` for one outside this instance.
    func key(ofExpandedID id: String) -> String? {
        let prefix = refID + String(NodeAddress.separator)
        guard id.hasPrefix(prefix) else { return nil }
        let key = String(id.dropFirst(prefix.count))
        if nodes[key] != nil { return key }
        // An instance root answers to its ref's key and its component root's id.
        var steps = key.split(separator: NodeAddress.separator).map(String.init)
        guard steps.count > 1 else { return nil }
        let root = steps.removeLast()
        let refKey = steps.joined(separator: String(NodeAddress.separator))
        return nodes[refKey]?.componentRootID == root ? refKey : nil
    }

    /// Whether a key names the node with `ancestor`'s key or one inside it.
    func key(_ key: String, isAtOrInside ancestor: String) -> Bool {
        var cursor: String? = key
        var seen: Set<String> = []
        while let current = cursor, seen.insert(current).inserted {
            if current == ancestor { return true }
            cursor = nodes[current]?.parentKey
        }
        return false
    }
}
