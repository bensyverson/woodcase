//
//  BatchErrorMessage+Preserved.swift
//  Woodcase
//

import Foundation

/// The refusal for writing a key the file carries but the model does not.
///
/// A newer Pen's key on a node is kept in ``PenNode/extras`` and written back unchanged,
/// but no verb edits it. An agent that reads the node with `get`, sees the key and tries
/// to `set` it gets ``EditingError/unknownProperty(nodeID:key:nodeType:)`` like any other
/// unknown path — and a bare "not a property" would contradict what `get` just printed.
/// So the refusal says the key is there, kept, and not editable.
extension BatchErrorMessage {
    /// The raw .pen key a refused path names when the node carries it as an extra, or `nil`.
    ///
    /// - Parameters:
    ///   - path: The path the caller wrote — `kind.layoutIncludeStroke`, or the raw key.
    ///   - nodeID: The node it was written to.
    ///   - document: The document the node is in.
    /// - Returns: The raw key, when the node's ``PenNode/extras`` hold it.
    static func preservedKey(_ path: String, on nodeID: String, in document: EditableDocument) -> String? {
        let raw = NodePropertyCodec.rawKey(for: path)
        guard document.node(id: nodeID)?.extras[raw] != nil else { return nil }
        return raw
    }

    /// The statement for a refused write to a preserved key.
    ///
    /// - Parameters:
    ///   - path: The path the caller wrote.
    ///   - raw: The raw key the node carries.
    ///   - nodeType: The node's type name.
    /// - Returns: The first half of the refusal.
    static func preservedStatement(_ path: String, raw: String, nodeType: String) -> String {
        """
        \(path) is not a property Woodcase models on a \(nodeType); the node's "\(raw)" is \
        kept as the file wrote it and written back unchanged, but it cannot be edited
        """
    }
}
