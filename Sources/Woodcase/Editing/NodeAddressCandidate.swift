//
//  NodeAddressCandidate.swift
//  Woodcase
//

import Foundation

/// One node an address could refer to: its id and its full name path.
///
/// Carried by ``EditingError/ambiguousAddress(address:candidates:)`` and
/// ``EditingError/addressNotFound(address:nearMisses:)`` so an error message can
/// list every candidate the way a caller would address it next time.
public struct NodeAddressCandidate: Friendly {
    /// An id-only address for this candidate: a plain node's id, or
    /// `"<refID>/<descendantKey>"` for a node inside a component instance.
    /// Either form resolves back to exactly this candidate.
    public var id: String

    /// The node's full name path from its root (`"Dashboard/Header/Title"`).
    /// Unnamed segments are rendered by the name-path formatter's unnamed marker.
    public var path: String

    public init(id: String, path: String) {
        self.id = id
        self.path = path
    }

    /// Whether this candidate is a node inside a component instance.
    ///
    /// Read off ``id``, which carries a `/` only in the `"<refID>/<descendantKey>"`
    /// form: a node id may not contain the address separator — that is what makes a
    /// path parseable at all — so the two forms cannot be confused.
    public var isInstanceDescendant: Bool {
        id.contains(NodeAddress.separator)
    }
}
