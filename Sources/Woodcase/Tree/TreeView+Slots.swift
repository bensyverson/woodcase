//
//  TreeView+Slots.swift
//  Woodcase
//

import Foundation

/// Where a row's node comes from, and which children go under it.
///
/// The walk in `TreeView.swift` reads the flat store, which is the whole answer for
/// every node a .pen file authors. It is not the whole answer inside a component
/// **instance**: an instance fills a slot frame by overriding its `children`, and those
/// children are inline .pen JSON in the instance's `descendants` map — in no store, and
/// invisible to a walk that only knows how to look one up. This is the half of the walk
/// that knows about them.
extension TreeView {
    /// Where the node a row describes comes from.
    ///
    /// Almost every row is a node in the flat store, named by id. The exception is a
    /// child an instance writes into a component's slot frame: the expansion is the
    /// first thing that gives it an id in any tree, so the walk has to carry the node
    /// itself rather than a name for it.
    enum Source {
        /// A node in ``EditableDocument/nodes``, by id.
        case stored(String)

        /// A node an instance injected, exactly as its override writes it.
        case injected(PenNode)

        /// The id the node answers to inside the instance chain it sits in.
        var nodeID: String {
            switch self {
            case let .stored(id): id
            case let .injected(node): node.id
            }
        }

        /// The node as it was authored, for a source that carries one — an injected
        /// node's only form, and `nil` for one the store holds.
        var authoredNode: PenNode? {
            switch self {
            case .stored: nil
            case let .injected(node): node
            }
        }
    }

    /// The children to walk under one row, in the order they render.
    ///
    /// Three sources, in the order the expansion reads them: an instance stands in for
    /// its component root, so its children are the component's; a node an override
    /// fills takes the children that override writes; anything else keeps its own.
    ///
    /// - Parameters:
    ///   - source: The row's node.
    ///   - componentRoot: The component root it stands in for, if any.
    ///   - prefix: The `ref` node ids it sits inside, outermost first.
    ///   - document: The document, for the store's children and the instances' overrides.
    /// - Returns: One source per child, in render order.
    static func childSources(
        of source: Source,
        componentRoot: String?,
        prefix: [String],
        in document: EditableDocument
    ) -> [Source] {
        if let componentRoot {
            return document.componentChildIDs(of: componentRoot).map { Source.stored($0) }
        }
        if let injected = document.injectedChildren(
            of: source.nodeID, insideInstances: prefix
        ) {
            return injected.map { Source.injected($0) }
        }
        switch source {
        case let .stored(id):
            return document.componentChildIDs(of: id).map { Source.stored($0) }
        case let .injected(node):
            return node.kind.inlineChildren.map { Source.injected($0) }
        }
    }
}
