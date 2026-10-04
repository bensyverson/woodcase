//
//  BatchApplier+Edit.swift
//  Woodcase
//

import Foundation

public extension BatchApplier {
    /// Applies one ``EditOperation`` the batch grammar has no verb for, through the same
    /// session funnel as every batch line.
    ///
    /// The grammar leaves a few writes out on purpose — removing a variable, a theme axis
    /// or an import alias, where an optional payload would turn a dropped field into a
    /// silent delete — so a caller that offers them (`woodcase vars rm`, a script's
    /// `doc.vars.rm`) hands the operation over directly. It still lands as a
    /// ``SessionOrigin/local(_:)`` submission: logged through `recorder` when there is
    /// one, otherwise through a transient session that records nothing.
    ///
    /// ```swift
    /// try BatchApplier.applyEdit(
    ///     .removeVariable(EditOperation.RemoveVariable(name: "brand")),
    ///     to: document, recorder: recorder
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    ///   - document: The document to edit.
    ///   - recorder: The transaction's ``ActivityRecorder``, when the edit should be
    ///     logged. `nil` logs nothing.
    /// - Returns: The committed change, with the edit's granular inverse.
    /// - Throws: The ``EditingError`` the document refused it with; nothing is written.
    @discardableResult
    static func applyEdit(
        _ operation: EditOperation,
        to document: EditableDocument,
        recorder: ActivityRecorder? = nil
    ) throws -> CommittedChange {
        try writingSession(editing: document, recorder: recorder)
            .submit(.local(LocalEdit(operations: [operation])))
    }
}
