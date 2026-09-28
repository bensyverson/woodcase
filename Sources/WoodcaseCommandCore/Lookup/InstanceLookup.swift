//
//  InstanceLookup.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Answers "who instances this component?" — the read side of the guard `rm` and
/// `replace` already enforce.
///
/// ``Woodcase/EditableDocument/instanceIDs(ofComponent:)`` is the library's answer and
/// this adds nothing to it but order: the ids come back in document order rather than
/// by name path, so the listing reads top-down like `tree` and like the file. `get
/// --instances` is a thin shell around this, the way `get` is around ``NodeLookup``.
enum InstanceLookup {
    /// Every `ref` that draws the component an address names.
    ///
    /// - Parameters:
    ///   - address: The definition, in any form
    ///     ``Woodcase/EditableDocument/resolve(_:tags:)-(String,_)`` accepts.
    ///   - document: The document to read.
    /// - Returns: The definition and its instances, in document order.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when the address names a
    ///   node that is not a reusable component — nothing can instance it, so an empty
    ///   list would be a plausible wrong answer; and whatever
    ///   ``Woodcase/EditableDocument/resolve(_:tags:)-(String,_)`` throws for an
    ///   address that names no single node.
    static func find(_ address: String, in document: EditableDocument) throws -> InstanceReport {
        let resolved = try document.resolve(address)
        guard case let .node(id) = resolved, document.componentRegistry[id] != nil else {
            throw notAComponent(address, resolved: resolved, in: document)
        }
        guard let revision = document.revision(of: id) else {
            throw EditingError.nodeNotFound(id: id)
        }

        let instances = Set(document.instanceIDs(ofComponent: id))
        let rows = document.nodeIDsInDocumentOrder()
            .filter(instances.contains)
            .compactMap { row(id: $0, in: document) }

        return InstanceReport(
            definition: InstanceReport.Row(id: id, address: document.namePath(of: id), rev: revision),
            instances: rows
        )
    }

    // MARK: - Rows

    /// One instance as a row, or `nil` for an id the document no longer holds.
    private static func row(id: String, in document: EditableDocument) -> InstanceReport.Row? {
        guard let revision = document.revision(of: id) else { return nil }
        return InstanceReport.Row(id: id, address: document.namePath(of: id), rev: revision)
    }

    // MARK: - Refusals

    /// The refusal for an address that names something no `ref` can point at.
    ///
    /// A node inside a component instance is included: it has no stored identity of
    /// its own, so it cannot be a component either. Both name `tree` as the next
    /// command, because "what is in here" is the question the caller most likely meant.
    private static func notAComponent(
        _ address: String,
        resolved: ResolvedNodeAddress,
        in document: EditableDocument
    ) -> CommandFailure {
        let path = document.namePath(of: resolved)
        return CommandFailure(
            message: "\(path) is not a reusable component, so no `ref` can instance it. Only a "
                + "node with `common.reusable=true` has instances — `woodcase tree <file>` marks "
                + "each of those with a `*`. Run `woodcase tree <file> \(address)` to see what "
                + "this one holds.",
            exitCode: .usage
        )
    }
}
