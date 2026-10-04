//
//  ChangeKey+Node.swift
//  Woodcase
//

import Foundation

extension ChangeKey {
    /// The node a key belongs to: the node itself, or the `ref` node for an override
    /// key; `nil` for a key of the document rather than of a node.
    ///
    /// An undo that would remove or rebuild a subtree asks which of the ledger's keys
    /// fall inside it, and this is how it tells.
    var nodeID: String? {
        switch self {
        case let .property(node, _), let .placement(node), let .existence(node):
            node
        case let .override(ref, _, _), let .rootOverride(ref, _):
            ref
        case .variable, .importAlias, .themeAxis, .document:
            nil
        }
    }
}
