//
//  PredicateFailureMessage.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase
import WoodcaseScripting

/// The sentence a refused or throwing `find` predicate earns on standard error.
///
/// Three things a reader needs and a stack trace loses: *where* — the line of the
/// predicate, quoted — *on what* — the row it was looking at when it threw, by address
/// and by id — and *what to do*, which is the sentence the host already wrote. The row
/// matters more here than in a script: a predicate that works for eight rows and throws
/// on the ninth is a statement about that node, not about the predicate.
enum PredicateFailureMessage {
    /// Renders a failure.
    ///
    /// - Parameters:
    ///   - error: What the host reported.
    ///   - row: The row the predicate threw on, when it threw on one.
    /// - Returns: The message to write, without a trailing newline.
    static func describe(_ error: ScriptError, row: TreeRow?) -> String {
        var opening = "The predicate"
        if let row {
            opening += " threw on row \(row.address) (\(row.id))"
        }
        if let line = error.line {
            opening += ", line \(line)"
        }
        var message = "\(opening): \(error.message)"
        if let quoted = error.sourceLine?.trimmingCharacters(in: .whitespaces), !quoted.isEmpty {
            message += "\n  \(quoted)"
        }
        return message
    }
}
