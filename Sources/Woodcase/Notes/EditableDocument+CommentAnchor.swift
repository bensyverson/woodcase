//
//  EditableDocument+CommentAnchor.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Whether a comment anchor's node is still in the document.
    ///
    /// The anchor stores ids, a plain node's or an instance child's expanded id path
    /// (`instance/child`), so each segment is resolved as an id and never as a name: a
    /// node later *named* like the deleted one's id must not revive the thread. An
    /// instance child a component edit removed no longer resolves, which is the
    /// deleted-node case too.
    ///
    /// - Parameter node: The anchor's `node`, as written.
    /// - Returns: Whether it names exactly one node, in the document or inside an instance.
    func resolvesCommentAnchor(_ node: String) -> Bool {
        let segments = node.split(separator: NodeAddress.separator, omittingEmptySubsequences: false)
        let address = segments.map { NodeAddress.marker(forID: String($0)) }.joined(separator: String(NodeAddress.separator))
        return (try? resolve(address)) != nil
    }
}
