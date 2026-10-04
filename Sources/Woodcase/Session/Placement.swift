//
//  Placement.swift
//  Woodcase
//

import Foundation

/// Where a node should land when an undo puts it back, anchored on a sibling.
///
/// An inverse captured as an absolute index goes wrong as soon as anyone else inserts
/// or removes a sibling in front of the spot. A placement instead remembers the
/// sibling the node sat *after*, and turns that into an index only when the inverse is
/// applied, so the node lands next to the same neighbor whatever else has changed.
///
/// Resolution, against the parent's children as they stand (the node itself left out):
///
/// - ``after`` is still a child of ``parentID``: the index just past it.
/// - ``after`` is `nil` (the node was first): index 0.
/// - The anchor has gone or moved away: ``fallbackIndex``, clamped to the sibling count.
/// - No fallback either: `nil`, which appends.
public struct Placement: Friendly {
    /// Creates a placement.
    ///
    /// - Parameters:
    ///   - parentID: The parent to land in, or `nil` for the document root.
    ///   - after: The sibling the node sat directly after, or `nil` if it was first.
    ///   - fallbackIndex: The index to use when the anchor is no longer a sibling.
    public init(parentID: String?, after: String?, fallbackIndex: Int?) {
        self.parentID = parentID
        self.after = after
        self.fallbackIndex = fallbackIndex
    }

    /// The parent to land in, or `nil` for the document root.
    public var parentID: String?

    /// The sibling the node sat directly after, or `nil` if it was first.
    public var after: String?

    /// The index to use when the anchor is no longer among the parent's children.
    public var fallbackIndex: Int?

    /// Where a node sits in a document now, as a placement that will find the spot again.
    ///
    /// - Parameters:
    ///   - nodeID: The node to locate.
    ///   - document: The document holding it.
    /// - Returns: The node's placement, or `nil` if the document has no such node.
    public static func of(_ nodeID: String, in document: EditableDocument) -> Placement? {
        guard document.nodes[nodeID] != nil else { return nil }
        let parentID = document.parents[nodeID]
        let siblings = siblingIDs(under: parentID, in: document)
        guard let index = siblings.firstIndex(of: nodeID) else { return nil }
        return Placement(
            parentID: parentID,
            after: index > 0 ? siblings[index - 1] : nil,
            fallbackIndex: index
        )
    }

    /// The index this placement resolves to for a node, against the document as it stands.
    ///
    /// - Parameters:
    ///   - nodeID: The node being placed. It is left out of the sibling list, which is
    ///     how a move and an insert both count positions.
    ///   - document: The document the node will land in.
    /// - Returns: The index among the remaining siblings, or `nil` to append.
    public func index(placing nodeID: String, in document: EditableDocument) -> Int? {
        let siblings = Self.siblingIDs(under: parentID, in: document).filter { $0 != nodeID }
        guard let after else { return 0 }
        if let anchor = siblings.firstIndex(of: after) {
            return anchor + 1
        }
        return fallbackIndex.map { min(max($0, 0), siblings.count) }
    }

    /// The ordered children of a parent, or the root order for `nil`.
    private static func siblingIDs(under parentID: String?, in document: EditableDocument) -> [String] {
        guard let parentID else { return document.rootOrder }
        return document.children[parentID] ?? []
    }
}
