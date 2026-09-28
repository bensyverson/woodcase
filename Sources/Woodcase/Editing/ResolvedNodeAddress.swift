//
//  ResolvedNodeAddress.swift
//  Woodcase
//

import Foundation

/// What a ``NodeAddress`` resolved to: a node in the document, or a node *inside* a
/// component instance, which the document can only reach through the instance's
/// override map.
///
/// The distinction is where an edit is stored. A ``node(id:)`` is edited in place. An
/// ``instanceDescendant(refID:descendantKey:)`` has no storage of its own — the edit
/// becomes an entry in the ref node's `descendants` map, keyed exactly as Pen keys it.
public enum ResolvedNodeAddress: Friendly {
    /// A node that exists in the flat store and is edited directly.
    case node(id: String)

    /// A node inside an expanded component instance.
    ///
    /// - Parameters:
    ///   - refID: The id of the outermost `ref` node — the instance that carries the override.
    ///   - descendantKey: The key Pen stores in that ref's `descendants` map: the
    ///     component-node ids from the outermost ref inward, joined by `/`. A node in
    ///     the component is just its id, at whatever depth the component nests it
    ///     (`"Lbl01"`); a node inside a nested instance is prefixed by that instance's
    ///     id (`"Bdg01/Cnt01"`).
    case instanceDescendant(refID: String, descendantKey: String)

    /// The id of the node that actually stores an edit to this target.
    ///
    /// For ``node(id:)`` that is the node itself; for an instance descendant it is the
    /// outermost ref, whose `descendants` map carries the override.
    public var targetID: String {
        switch self {
        case let .node(id): id
        case let .instanceDescendant(refID, _): refID
        }
    }

    /// The `descendants` key for an instance descendant, or `nil` for a plain node.
    public var descendantKey: String? {
        switch self {
        case .node: nil
        case let .instanceDescendant(_, key): key
        }
    }

    /// The address, written entirely in ids, that resolves back to this target.
    ///
    /// A plain node is its own id; an instance descendant is the ref id and the
    /// descendant key joined by `/` (`"Nav01/Bdg01/Cnt01"`). This is the form used to
    /// name candidates in ``EditingError/ambiguousAddress(address:candidates:)``: it
    /// names every step by id, so it distinguishes candidates a name path cannot.
    public var address: String {
        switch self {
        case let .node(id): id
        case let .instanceDescendant(refID, key): "\(refID)\(NodeAddress.separator)\(key)"
        }
    }
}
