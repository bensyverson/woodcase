//
//  MergeResolution.swift
//  Woodcase
//

import Foundation

/// What a three-way merge decided, as the target state of every part of the local
/// document it changes — before any of it becomes an ``EditOperation``.
///
/// Sparse by design: a node, list or document key the merge leaves as the local side
/// has it does not appear, so a merge of two small edits to a large document stays
/// small. The op sequencer reads the values it needs from the external document.
struct MergeResolution: Friendly {
    /// The merged state of every node the merge adds to the local document or changes
    /// in it — its own content, its parent and its child list — keyed by id.
    var nodes: [String: NodeChange.State] = [:]

    /// The local nodes the merge removes, whole subtrees listed node by node.
    var removed: Set<String> = []

    /// The merged order of the top-level nodes, or `nil` when it is the local order.
    var rootOrder: [String]?

    /// The document-level keys that take the external document's value.
    /// ``DocumentChangeKey/rootOrder`` is never among them; see ``rootOrder``.
    var document: Set<DocumentChangeKey> = []

    /// Everything the merge could not take from both sides, in a stable order.
    var conflicts: [MergeConflict] = []
}
