//
//  CRDTStateTransfer+Validation.swift
//  Woodcase
//

import Foundation

public extension CRDTStateTransfer {
    /// Checks a transfer another peer sent before a replica joins from it.
    ///
    /// The snapshot is checked as ``CRDTSnapshot/validate()`` checks it, and the document
    /// must hold no node the snapshot has deleted — a sign the two were not taken
    /// together.
    ///
    /// - Throws: The snapshot's ``RemoteInputError``, or
    ///   ``RemoteInputError/transferDisagrees(nodeID:)``.
    func validate() throws(RemoteInputError) {
        try snapshot.validate()
        var pending = document.children
        while let node = pending.popLast() {
            if snapshot.tombstones.contains(node.id) {
                throw .transferDisagrees(nodeID: node.id)
            }
            pending += node.kind.inlineChildren
        }
    }
}
