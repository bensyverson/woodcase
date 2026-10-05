//
//  ComponentGraphView.swift
//  Woodcase
//

import Foundation

/// The component graph of a document as one ``ComponentGraphEdit`` would leave it: the
/// flat store — the document's own nodes, then its imported components — read through the
/// edit's overlay.
///
/// Not `Friendly`, on purpose: it reads a live ``EditableDocument``, and lives only for
/// the length of one check.
struct ComponentGraphView {
    /// The document the edit applies to.
    let document: EditableDocument

    /// The edit, laid over the document.
    let edit: ComponentGraphEdit

    /// A node after the edit, children stripped.
    func node(_ id: String) -> PenNode? {
        if let entry = edit.nodes[id] { return entry }
        return document.componentNode(id)
    }

    /// Whether a `ref` naming `id` would place a component after the edit.
    func isComponent(_ id: String) -> Bool {
        if let entry = edit.nodes[id] { return entry?.common.reusable == true }
        return document.reusableComponent(id) != nil
    }

    /// A node's children after the edit.
    func children(of id: String) -> [String] {
        edit.children[id] ?? document.componentChildIDs(of: id)
    }

    /// A node's parent after the edit.
    func parent(of id: String) -> String? {
        if let entry = edit.parents[id] { return entry }
        return document.componentParentID(of: id)
    }

    /// The components rendered anywhere in a component's subtree after the edit.
    ///
    /// - Parameter component: The component's id.
    /// - Returns: The component ids, sorted, none repeated.
    func targets(of component: String) -> [String] {
        var found: Set<String> = []
        var pending = [component]
        var seen: Set<String> = []
        while let id = pending.popLast() {
            guard seen.insert(id).inserted, let node = node(id) else { continue }
            for target in node.renderedComponentIDs + (edit.rendered[id] ?? []) where isComponent(target) {
                found.insert(target)
            }
            pending += children(of: id)
        }
        return found.sorted()
    }

    /// Every component at or above any of the given nodes after the edit, sorted.
    ///
    /// - Parameter sites: The nodes.
    /// - Returns: The components' ids.
    func components(atOrAbove sites: [String]) -> [String] {
        var found: Set<String> = []
        var seen: Set<String> = []
        for site in sites {
            var cursor: String? = site
            while let id = cursor, seen.insert(id).inserted {
                if isComponent(id), node(id) != nil { found.insert(id) }
                cursor = parent(of: id)
            }
        }
        return found.sorted()
    }
}
