//
//  CreatedNode.swift
//  Woodcase
//

import Foundation

/// A node a batch line created, and everything created under it.
///
/// This is a mutating verb's answer to "what did you make?": a tree mirroring
/// the inserted subtree, pairing each node's name with the id the document
/// actually gave it. An `add` keeps the ids its subtree supplied and draws the
/// rest; a `cp` draws all of them. Either way this is where the caller learns
/// what the document settled on, without a second read.
///
/// ```json
/// {"id":"k2Bq9","name":"Hero","children":[{"id":"Tz01m","name":"Caption","children":[]}]}
/// ```
public struct CreatedNode: Friendly {
    /// Creates a record of one created node.
    ///
    /// - Parameters:
    ///   - id: The id the document gave the node.
    ///   - name: The node's `common.name`, or `nil` for a node with none.
    ///   - children: The nodes created beneath it, in document order.
    public init(id: String, name: String? = nil, children: [CreatedNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    /// The id the document gave the node.
    public var id: String

    /// The node's `common.name`, or `nil` for a node with none.
    ///
    /// A node ``BatchOperation/add(_:)`` creates always has one; a node copied
    /// out of a file we did not write may not.
    public var name: String?

    /// The nodes created beneath this one, in document order.
    public var children: [CreatedNode]

    /// Every id in the created subtree, outermost first.
    public var allIDs: [String] {
        [id] + children.flatMap(\.allIDs)
    }
}
