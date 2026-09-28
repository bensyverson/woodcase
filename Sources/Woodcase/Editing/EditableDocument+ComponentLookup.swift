//
//  EditableDocument+ComponentLookup.swift
//  Woodcase
//

import Foundation

/// Lookups for a walk that follows a `ref` into its component — which may be one of
/// the document's own or one its imports define.
///
/// The flat store (``EditableDocument/nodes``, ``EditableDocument/children``,
/// ``EditableDocument/componentRegistry``) holds only what the file holds, and must: it
/// is what is written, revised, searched and deleted. An imported component is none of
/// those things, but an instance of one still has override keys, name paths and
/// addressable descendants, and ``PenRefExpander`` expands it. Every walk that has to
/// agree with that expansion reads through these instead of the store, and they answer
/// from the document's own store first and ``ImportedComponentStore`` second — the same
/// precedence the expander's registry gives a component id both define.
extension EditableDocument {
    /// A node a component walk may meet: the document's own, or an imported one.
    ///
    /// - Parameter id: The node id — prefixed (`"V:Cmp01"`) for an imported node.
    /// - Returns: The node, children stripped, or `nil`.
    func componentNode(_ id: String) -> PenNode? {
        nodes[id] ?? importedStore.nodes[id]
    }

    /// The ordered child ids of a node a component walk may meet.
    ///
    /// - Parameter id: The node id.
    /// - Returns: Its children's ids, or an empty array.
    func componentChildIDs(of id: String) -> [String] {
        if nodes[id] != nil { return children[id] ?? [] }
        return importedStore.children[id] ?? []
    }

    /// The parent of a node a component walk may meet.
    ///
    /// - Parameter id: The node id.
    /// - Returns: Its parent's id, or `nil` for a root or an imported component root.
    func componentParentID(of id: String) -> String? {
        if nodes[id] != nil { return parents[id] }
        return importedStore.parents[id]
    }

    /// The reusable node a `ref` of this id instantiates: the document's own, or an
    /// imported one.
    ///
    /// - Parameter id: The component id a `ref` names.
    /// - Returns: The component's root, children stripped, or `nil` when neither the
    ///   document nor its imports define one.
    func reusableComponent(_ id: String) -> PenNode? {
        componentRegistry[id] ?? importedStore.reusables[id]
    }

    /// The ancestors of a node a component walk may meet, nearest first, stopping at
    /// the first id already seen.
    ///
    /// - Parameter id: The node id.
    /// - Returns: Its ancestors' ids.
    func componentAncestors(of id: String) -> [String] {
        var result: [String] = []
        var seen: Set<String> = [id]
        var current = id
        while let parent = componentParentID(of: current), seen.insert(parent).inserted {
            result.append(parent)
            current = parent
        }
        return result
    }
}
