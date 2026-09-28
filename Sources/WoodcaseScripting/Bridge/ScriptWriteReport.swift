//
//  ScriptWriteReport.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// Turns one applied ``Woodcase/BatchLineResult`` into the ``Woodcase/WriteReport``
    /// the matching verb answers with.
    ///
    /// There is nothing to decide here and that is the point: every rule below is copied
    /// from the verb it belongs to, so a script's read-back and a terminal's three lines
    /// are the same value. The rules differ per verb because the *subject* does:
    ///
    /// | Verb | Leads with | Revision |
    /// | --- | --- | --- |
    /// | `set`, `mv` | the node it acted on | that node's, after |
    /// | `override` | the **instance**, not the descendant path | the instance's |
    /// | `rm` | the node it deleted, named before it went | none — it is gone |
    /// | `add`, `replace` | the subtree it made | the created root's |
    /// | `cp` | the copy, and every copy `each` made | the copy's |
    /// | `vars`, `themes`, `imports` | the name written | none — the subject is not a node |
    ///
    /// Two of them need a fact from *before* the write — an id the delete is about to
    /// invalidate, an instance the address only names by walking through it — so the
    /// subject is taken first and handed back in.
    enum ScriptWriteReport {
        /// What a report needs from the document before the write happens.
        struct Subject {
            /// The node the write acts on, where the verb resolves one up front.
            let id: String?

            /// That node's name path, taken before the write for a delete — afterwards
            /// there is no node to name, and `#id` is not what the caller typed.
            let path: String?

            /// Nothing to take: the operation creates its subject, or has none.
            static let none = Subject(id: nil, path: nil)
        }

        /// Resolves whatever the report will need before the operation is applied.
        ///
        /// - Parameters:
        ///   - operation: The operation about to be applied.
        ///   - document: The document as it stands.
        /// - Returns: The subject, empty for an operation that creates one.
        /// - Throws: ``Woodcase/EditingError`` when the address names nothing, which is
        ///   the same refusal, in the same place, the verb raises.
        static func subject(
            of operation: BatchOperation,
            in document: EditableDocument
        ) throws -> Subject {
            switch operation {
            case let .set(op):
                return try Subject(id: document.resolve(op.target).targetID, path: nil)
            case let .mv(op):
                return try Subject(id: document.resolve(op.target).targetID, path: nil)
            case let .override(op):
                return try Subject(id: document.resolve(op.target).targetID, path: nil)
            case let .rm(op):
                let id = try document.resolve(op.target).targetID
                return Subject(id: id, path: document.namePath(of: id))
            case .add, .replace, .cp, .variable, .themeAxis, .importOp:
                return Subject.none
            }
        }

        /// The report for one applied operation.
        ///
        /// - Parameters:
        ///   - operation: The operation that was applied.
        ///   - result: What the applier answered with.
        ///   - subject: What ``subject(of:in:)`` took before the write.
        ///   - document: The document as the write left it.
        /// - Returns: The report, in the shape the matching verb prints.
        static func report(
            of operation: BatchOperation,
            _ result: BatchLineResult,
            subject: Subject,
            in document: EditableDocument
        ) -> WriteReport {
            switch operation {
            case .set, .mv, .override:
                acted(on: subject, result, in: document)
            case .rm:
                WriteReport(
                    path: subject.path,
                    id: subject.id,
                    documentRevision: document.documentRevision,
                    divergences: result.divergences
                )
            case .add, .replace:
                created(result, leadingWith: result.created.first?.id, in: document)
            case .cp:
                created(result, leadingWith: result.id, in: document)
            case let .variable(op):
                named(op.name, in: document)
            case let .themeAxis(op):
                named(op.name, in: document)
            case let .importOp(op):
                named(op.alias, in: document)
            }
        }

        // MARK: - Private

        /// The report for a verb that acted on a node that already existed.
        private static func acted(
            on subject: Subject,
            _ result: BatchLineResult,
            in document: EditableDocument
        ) -> WriteReport {
            WriteReport(
                path: result.path ?? subject.id.map(document.namePath(of:)),
                id: subject.id,
                nodeRevision: subject.id.flatMap { document.revision(of: $0) },
                documentRevision: document.documentRevision,
                node: result.node,
                divergences: result.divergences
            )
        }

        /// The report for a verb that made something, leading with what it made.
        private static func created(
            _ result: BatchLineResult,
            leadingWith id: String?,
            in document: EditableDocument
        ) -> WriteReport {
            WriteReport(
                created: result.created,
                path: result.path,
                id: id,
                nodeRevision: id.flatMap { document.revision(of: $0) },
                documentRevision: document.documentRevision,
                node: result.node,
                divergences: result.divergences
            )
        }

        /// The report for a write whose subject is a name in the document's own tables.
        ///
        /// A variable, a theme axis and an import alias are not nodes, so there is no id
        /// and no node revision to carry. ``Woodcase/WriteReport/path`` holds the name
        /// that was written, which is what a transcript line needs to say *which* one
        /// moved; a `nil` there would make every document-level write read alike.
        private static func named(_ name: String, in document: EditableDocument) -> WriteReport {
            WriteReport(path: name, documentRevision: document.documentRevision)
        }
    }

#endif
