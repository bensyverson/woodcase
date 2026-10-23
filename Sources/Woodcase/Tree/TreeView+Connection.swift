//
//  TreeView+Connection.swift
//  Woodcase
//

import Foundation

extension TreeView {
    /// A connection's two ends as a row reports them, or `nil` for any other node.
    ///
    /// An end's name is its node's — for an `instance/child` path, the node its last id
    /// names, since that is the node the end sits on.
    ///
    /// - Parameters:
    ///   - node: The node the row is for.
    ///   - document: The document, for the ends' names.
    /// - Returns: The ends.
    static func connectionEnds(of node: PenNode, in document: EditableDocument) -> TreeRow.Connection? {
        guard case let .connection(data) = node.kind else { return nil }
        func end(_ endpoint: PenNode.ConnectionData.Endpoint) -> TreeRow.Connection.End {
            let last = endpoint.path.split(separator: "/").last.map(String.init) ?? endpoint.path
            let named = document.node(id: endpoint.path) ?? document.node(id: last)
            return TreeRow.Connection.End(path: endpoint.path, anchor: endpoint.anchor.rawValue, name: named?.common.name)
        }
        return TreeRow.Connection(source: end(data.source), target: end(data.target))
    }
}
