//
//  OpSequencer.swift
//  Woodcase
//

import Foundation

/// Turns a ``MergeResolution`` into the ``EditOperation``s that take the local
/// document there, in an order each of them applies in
/// (`project/2026-10-04-three-way-diff-design.md`, algorithm step 5).
///
/// The order, phase by phase:
///
/// 1. Imports, theme axes and variables the merge adds or changes, then the root's
///    own properties — so every node written later can resolve what it names.
/// 2. Nodes that become containers are retyped, so children can move into them.
/// 3. The structural pass: every child list the merge changes, parents before
///    children, is made left to right by inserting new subtrees and moving existing
///    nodes to absolute indices. A node leaving a list drifts to its tail until it is
///    moved or deleted, and since a parent's own place is final before its list is
///    made, no move can put a node under itself.
/// 4. Each kept node's content, as `setProperties` — after the structure, so a ref
///    retargeted to a new component finds it.
/// 5. Nodes that become leaves and hold no children by now are retyped — an instance
///    that stops being one must let go of its component before the component's delete.
///    Then deletes, topmost nodes only, subtrees holding no component first.
/// 6. The other nodes that become leaves are retyped, now that their children are
///    gone; then each container left empty gets its declared `"children": []`, or
///    loses it.
/// 7. Variables, imports and theme axes the merge removes, then whether each table
///    is declared.
///
/// It tracks the child lists its own operations change, so each index it emits is
/// valid at the moment its operation applies.
struct OpSequencer {
    /// The merged state to reach.
    let resolution: MergeResolution

    /// The local document the operations apply to.
    let ours: EditableDocument

    /// The external document, which holds the values of the document keys the merge takes.
    let theirs: EditableDocument

    /// The operations so far, in order.
    var operations: [EditOperation] = []

    /// Each child list the operations have changed, as it stands after them; `nil`
    /// is a container that declares none. Lists absent here are the local ones.
    var lists: [String: [String]?] = [:]

    /// The top-level order after the operations so far, once one has changed it.
    var topLevel: [String]?

    /// The parent of each node the operations have placed; `.some(nil)` is the top level.
    var placedParent: [String: String?] = [:]

    /// Each node's content as it stands after the operations so far, where it is not
    /// the local content.
    var current: [String: PenNode] = [:]

    /// Creates a sequencer.
    ///
    /// - Parameters:
    ///   - resolution: The merged state.
    ///   - ours: The local document.
    ///   - theirs: The external document.
    init(resolution: MergeResolution, ours: EditableDocument, theirs: EditableDocument) {
        self.resolution = resolution
        self.ours = ours
        self.theirs = theirs
    }

    /// Sequences the merge.
    ///
    /// - Returns: The operations, to apply to the local document in order.
    mutating func run() -> [EditOperation] {
        addDocumentEntries()
        retypeToContainers()
        buildStructure()
        writeContents()
        retypeToLeaves(childlessOnly: true)
        deleteRemoved()
        retypeToLeaves(childlessOnly: false)
        declareEmptyChildren()
        removeDocumentEntries()
        return operations
    }

    // MARK: - The merged tree

    /// Whether a node is one the merge adds — the local document does not hold it.
    func isNew(_ id: String) -> Bool {
        ours.nodes[id] == nil
    }

    /// A node as the merged document holds it.
    ///
    /// - Parameter id: The id of a node in the merged document.
    func finalState(of id: String) -> NodeChange.State? {
        if let state = resolution.nodes[id] { return state }
        guard let node = ours.nodes[id] else { return nil }
        return NodeChange.State(node: node, parentID: ours.parents[id], children: ours.children[id])
    }

    /// A container's child list in the merged document — or the top level's, for `nil`.
    func finalChildren(of parent: String?) -> [String] {
        guard let parent else { return resolution.rootOrder ?? ours.rootOrder }
        return finalState(of: parent)?.children ?? []
    }

    // MARK: - The document so far

    /// A container's child list after the operations so far; `nil` when it declares none.
    func list(of parent: String) -> [String]? {
        if let entry = lists[parent] { return entry }
        return ours.children[parent]
    }

    /// A node's parent after the operations so far.
    func parentNow(of id: String) -> String? {
        if let entry = placedParent[id] { return entry }
        return ours.parents[id]
    }

    /// A node's content after the operations so far.
    func contentNow(of id: String) -> PenNode? {
        current[id] ?? ours.nodes[id]
    }

    /// Takes a node out of the list it sits in now.
    mutating func detach(_ id: String) {
        if let parent = parentNow(of: id) {
            var siblings = list(of: parent) ?? []
            siblings.removeAll { $0 == id }
            lists[parent] = .some(siblings)
        } else {
            var roots = topLevel ?? ours.rootOrder
            roots.removeAll { $0 == id }
            topLevel = roots
        }
    }

    /// Puts a node into a list at `index`, as an insert or a move does.
    mutating func attach(_ id: String, to parent: String?, at index: Int) {
        if let parent {
            var siblings = list(of: parent) ?? []
            siblings.insert(id, at: index)
            lists[parent] = .some(siblings)
        } else {
            var roots = topLevel ?? ours.rootOrder
            roots.insert(id, at: index)
            topLevel = roots
        }
        placedParent[id] = .some(parent)
    }
}
