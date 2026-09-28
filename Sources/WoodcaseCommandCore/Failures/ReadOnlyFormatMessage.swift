//
//  ReadOnlyFormatMessage.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The sentence a write verb prints when the file declares another major version.
///
/// ``PenFormatWriteRefusal`` says which file, which two versions, and that the file is
/// read-only. Standing at a shell, the next step is to know that reading still works
/// and what it would take to write:
///
/// ```
/// Cannot write /w/design.pen: it declares .pen format 3.0, a different major version
/// from the 2.19 this build models, so it is read-only — the read verbs (`woodcase tree`,
/// `get`, `lint`, `render`, `shot`) still work; to edit it, update Woodcase to a build
/// that writes 3.x, or edit it in Pen.
/// ```
///
/// Every write verb prints this one, and so does `woodcase migrate` for each file it
/// refuses.
enum ReadOnlyFormatMessage {
    /// The whole sentence: the refusal, then what still works and what to do.
    ///
    /// - Parameter refusal: The refused write.
    /// - Returns: One line for standard error.
    static func describe(_ refusal: PenFormatWriteRefusal) -> String {
        "\(refusal) — the read verbs (`woodcase tree`, `get`, `lint`, `render`, `shot`) still work; "
            + "to edit it, update Woodcase to a build that writes \(refusal.declared.major).x, or edit it in Pen."
    }
}
