//
//  DocumentSession+ForeignWrite.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

extension DocumentSession {
    /// Applies an edit as another author would, until the remote origin lands: the
    /// document changes, the change takes the next sequence, and its keys are stamped
    /// under that author — nothing joins the local author's undo or redo history.
    ///
    /// - Parameters:
    ///   - operation: The other author's edit.
    ///   - author: Who made it.
    func simulateForeignWrite(_ operation: EditOperation, by author: Author) throws {
        let keys = try ChangeKey.keys(of: operation, in: document)
        try document.apply(operation)
        sequence += 1
        ledger.stamp(keys, by: author, at: sequence)
    }
}
