//
//  EditableDocument+StructuralLayout.swift
//  Woodcase
//

import Foundation

/// What an insert, move or delete requires laying out again.
///
/// A structural edit changes the layout of the containers it touches — the parent a
/// node leaves, the parent it enters — and their ancestors, and nothing else: every
/// sibling keeps its subtree and moves at most, so a node-granular pass
/// (``PenLayoutState/update(to:invalidation:)``) answers it from memory. So the edit
/// names the *spine* of every touched node (leaf `df281f`), not the board around it.
///
/// An edit inside a component reaches further: expansion carries it into every placed
/// instance of the component, and of every component nesting it, where no source id
/// names the nodes it changed. Those instances' refs are named with their spines
/// (``layoutInstancesDrawing(_:)``): each instance is laid out whole, and the rest of
/// its board answers from memory.
///
/// The scope is read *before and after* the mutation, for the same reason
/// ``invalidatingCaches(touching:_:)`` reads its rule twice: a delete or a move out of a
/// parent or component only shows where it was beforehand, an insert or a move in only
/// where it went afterwards.
extension EditableDocument {
    /// Runs a structural mutation, marking for layout only the spines it touches and
    /// those of the instances drawing a component it touched.
    ///
    /// Does nothing beyond running `body` when the layout cache is absent or already
    /// needs a full pass: there is nothing finer to keep.
    ///
    /// - Parameters:
    ///   - subjects: The nodes the mutation touches — every node it inserts or
    ///     deletes, the node it moves, and the parent it lands under. Ids that name
    ///     nothing are ignored.
    ///   - body: The mutation.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws. The scope is still recorded, because a
    ///   throwing operation may have written before it threw.
    func invalidatingLayout<T>(structurallyTouching subjects: [String], _ body: () throws -> T) rethrows -> T {
        guard let cache = _layoutCache, !cache.isFullyInvalidated else { return try body() }
        let before = structuralLayoutSpine(of: subjects)
        defer {
            // The index the after-reading walks must know what the inserted nodes render.
            reindexReferrers(of: subjects)
            let spine = before.union(structuralLayoutSpine(of: subjects))
            cache.invalidateStructure(subjects: Set(subjects.filter { spine.contains($0) }), spine: spine)
        }
        return try body()
    }

    /// The layout scope of a set of touched nodes, as the document stands now.
    ///
    /// - Parameter subjects: The touched nodes.
    /// - Returns: Their spines and — when one of them is a component or inside one — the
    ///   spines of the instances that draw an affected component.
    func structuralLayoutSpine(of subjects: [String]) -> Set<String> {
        var spine: Set<String> = []
        var components: Set<String> = []
        for subject in subjects where nodes[subject] != nil {
            var current = subject
            // Stop at a visited node: subjects of one subtree share their spine.
            while spine.insert(current).inserted {
                if nodes[current]?.common.reusable == true { components.insert(current) }
                guard let parent = parents[current], nodes[parent] != nil else { break }
                current = parent
            }
        }
        for ref in layoutInstancesDrawing(Array(components)) {
            spine.insert(ref)
            spine.formUnion(ancestors(of: ref))
        }
        return spine
    }
}
