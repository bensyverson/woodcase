//
//  DocumentLinter+Imports.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/importNotFound``, ``LintCheck/importUnreadable`` and
/// ``LintCheck/importNotFollowed`` checks, and what ``LintCheck/brokenRef`` says about
/// an instance that reaches through an import.
///
/// The document was read with the libraries its `imports` name
/// (``EditableDocument/readContext``), so an instance of `V:Button` is judged against
/// the library that defines it, like any instance of the document's own components. An
/// import that brought nothing in is reported once, at the top, from the problems the
/// read recorded — a missing library is a finding, never a failed lint.
extension DocumentLinter {
    /// One document-level finding per import problem, in the order the read met them.
    ///
    /// - Parameter document: The document, with its read context.
    /// - Returns: The findings, carrying no node.
    static func importFindings(in document: EditableDocument) -> [LintFinding] {
        document.readContext.libraries.problems.map { problem in
            LintFinding(check: check(for: problem), nodeID: nil, path: nil, message: "This document \(problem.message)")
        }
    }

    /// The check a problem is a finding of.
    private static func check(for problem: PenImportProblem) -> LintCheck {
        switch problem {
        case .notFound, .bundled, .remote: .importNotFound
        case .unreadable: .importUnreadable
        case .notFollowed: .importNotFollowed
        }
    }

    /// What a broken ref's finding says: where the component was looked for.
    ///
    /// An id prefixed with a declared alias was looked for in that alias's library, and
    /// saying which file is the difference between "fix the ref" and "fix the import".
    ///
    /// - Parameters:
    ///   - componentID: The id the `ref` names.
    ///   - document: The document the ref is in.
    /// - Returns: The finding's message.
    static func brokenRefMessage(for componentID: String, in document: EditableDocument) -> String {
        let alias = componentID.split(separator: ":", maxSplits: 1).first.map(String.init)
        guard componentID.contains(":"), let alias, let path = document.imports?[alias] else {
            return "is an instance of `\(componentID)`, which this document defines no reusable node for; "
                + "it renders as nothing."
        }
        guard document.readContext.libraries.documents[path] != nil else {
            return "is an instance of `\(componentID)`, from `\(path)` (imported as `\(alias)`), which could "
                + "not be read — see the import finding above; it renders as nothing."
        }
        return "is an instance of `\(componentID)`, which `\(path)` (imported as `\(alias)`) defines no "
            + "reusable node for; it renders as nothing."
    }
}
