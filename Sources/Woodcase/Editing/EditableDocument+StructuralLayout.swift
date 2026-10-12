//
//  EditableDocument+StructuralLayout.swift
//  Woodcase
//

import Foundation

/// Which top-level boards an insert, move or delete can change (Penumbra ruling R20).
///
/// A structural edit changes the layout of the board that holds it and nothing else —
/// unless it lands inside a component. Then every board that draws the component
/// changes too, and so does every board that draws a component nesting one of those,
/// and so on. Every other board keeps its rects.
///
/// The scope is read *before and after* the mutation, for the same reason
/// ``invalidatingCaches(touching:_:)`` reads its rule twice: a delete or a move out of a
/// board or component only shows where it was beforehand, an insert or a move in only
/// where it went afterwards.
///
/// This is the root-granular step; a node-granular engine replaces the body of
/// ``invalidatingLayout(structurallyTouching:_:)`` without changing its callers.
extension EditableDocument {
    /// What a structural edit requires laying out again.
    struct StructuralLayoutScope: Friendly {
        /// The touched nodes and every ancestor above them, by source id.
        var spine: Set<String> = []

        /// The top-level nodes to lay out whole, by source id.
        var roots: Set<String> = []

        /// Both scopes together.
        ///
        /// - Parameter other: The scope to add.
        /// - Returns: The union of the two.
        func union(_ other: StructuralLayoutScope) -> StructuralLayoutScope {
            StructuralLayoutScope(spine: spine.union(other.spine), roots: roots.union(other.roots))
        }
    }

    /// Runs a structural mutation, marking for layout only the boards it can change.
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
        let before = structuralLayoutScope(of: subjects)
        defer {
            // The index the after-reading walks must know what the inserted nodes render.
            reindexReferrers(of: subjects)
            let scope = before.union(structuralLayoutScope(of: subjects))
            cache.invalidateStructure(spine: scope.spine, roots: scope.roots)
        }
        return try body()
    }

    /// The layout scope of a set of touched nodes, as the document stands now.
    ///
    /// - Parameter subjects: The touched nodes.
    /// - Returns: Their spines, the top-level nodes holding them, and — when one of
    ///   them is a component or inside one — every top-level node that draws an
    ///   affected component.
    func structuralLayoutScope(of subjects: [String]) -> StructuralLayoutScope {
        var scope = StructuralLayoutScope()
        var components: Set<String> = []
        for subject in subjects where nodes[subject] != nil {
            var current = subject
            // Stop at a visited node: subjects of one subtree share their spine.
            while scope.spine.insert(current).inserted {
                if nodes[current]?.common.reusable == true { components.insert(current) }
                guard let parent = parents[current], nodes[parent] != nil else { break }
                current = parent
            }
            scope.roots.insert(topLevelID(of: subject))
        }
        if !components.isEmpty {
            scope.roots.formUnion(layoutRootsDrawing(Array(components)))
        }
        return scope
    }

    /// The top-level node holding a node, or the node itself at the top level.
    ///
    /// - Parameter nodeID: The node.
    /// - Returns: The id of its outermost ancestor.
    func topLevelID(of nodeID: String) -> String {
        ancestors(of: nodeID).last ?? nodeID
    }
}
