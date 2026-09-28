//
//  BatchApplier+CopyLine.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Applies one `cp` line: every copy it makes, and every assignment inside each.
    ///
    /// A copy is the one write that cannot be fully planned in advance. Its
    /// path-keyed properties name nodes *inside* the copy, which does not exist until
    /// the insert has run — and, when the source is a reusable component, the copy is a
    /// `ref` whose descendants have no storage of their own, so the same key becomes an
    /// override rather than a set. So the line is planned copy by copy, against the
    /// document as each copy leaves it.
    ///
    /// What it *can* check in advance, it does: every path-keyed key is resolved against
    /// the **source** before the first insert, because a copy is name-for-name the node
    /// it came from. That is what makes an `each` of forty rows all-or-nothing in the
    /// message as well as in the file — a typo on row 39 is named before row 1 is
    /// written.
    ///
    /// - Parameters:
    ///   - op: The `cp` line.
    ///   - document: The document to edit.
    ///   - tags: Tag name → node id, for addressing what earlier lines created.
    ///   - recorder: The transaction's recorder, or `nil` to log nothing.
    ///   - undo: The line's undo stack, extended with every edit applied.
    ///   - outcome: The line's answer, extended with each copy's created tree.
    /// - Throws: ``BatchError/copyPathNotInSource(row:key:source:)`` for a key that names
    ///   nothing inside the source, ``BatchError/emptyCopyRows`` and
    ///   ``BatchError/copyTagWithRows(tag:)`` for a misused `each`, and whatever the
    ///   document refuses an edit with.
    static func performCopy(
        _ op: BatchOperation.CopyOp,
        on document: EditableDocument,
        tags: [String: String],
        recorder: ActivityRecorder?,
        undo: inout [[EditOperation]],
        into outcome: inout LineOutcome
    ) throws {
        let rows = try copyRows(of: op)
        let sourceID = try nodeID(op.source, in: document, tags: tags)
        // A key may be a name the source *publishes* rather than a path, so the
        // parameter list is read once and every row is split through it.
        let parameters = document.parameters(ofComponent: sourceID)
        try refuseUnknownPaths(
            in: rows, copying: sourceID, numbered: op.each != nil,
            parameters: parameters, in: document
        )

        for (index, row) in rows.enumerated() {
            let split = CopyAssignment.split(row, parameters: parameters)
            let insert = try planCopyInsert(
                oneCopy(of: op, root: split.root, offsetBy: index), in: document, tags: tags
            )
            let rootID = insert.rootID
            try apply(insert.plan, to: document, recorder: recorder, undo: &undo, into: &outcome)

            for (path, props) in split.descendants.sorted(by: { $0.key < $1.key }) {
                guard let target = CopyAssignment.address(inside: rootID, path: path) else { continue }
                let assignment = CopyAssignment.assignment(to: target, props: props, in: document)
                let inner = try plan(assignment, in: document, tags: [:])
                try apply(inner, to: document, recorder: recorder, undo: &undo, into: &outcome)
            }

            // Read back *after* the assignments: a key may have renamed a node inside
            // the copy, and the answer has to be the names on disk.
            outcome.created.append(createdTree(rootID: rootID, in: document))
            if op.each == nil {
                outcome.path = document.namePath(of: rootID)
                outcome.id = rootID
                outcome.node = document.node(id: rootID)
            }
        }
    }

    // MARK: - The rows

    /// The property maps a `cp` line copies with, one per copy it will make.
    ///
    /// A line without `each` makes exactly one copy, from `props` as written — no
    /// substitution, because there is no row number to substitute. A line with `each`
    /// makes one copy per row: `props` are the defaults, the row is laid over them, and
    /// ``CopyAssignment/rowPlaceholder`` becomes the 1-based row number in every value.
    ///
    /// - Parameter op: The `cp` line.
    /// - Returns: One property map per copy, in row order.
    /// - Throws: ``BatchError/copyTagWithRows(tag:)`` for a tag on an `each` line, and
    ///   ``BatchError/emptyCopyRows`` for an `each` with no rows.
    static func copyRows(of op: BatchOperation.CopyOp) throws -> [[String: AnyCodable]] {
        let defaults = op.props ?? [:]
        guard let each = op.each else { return [defaults] }
        if let tag = op.tag {
            throw BatchError.copyTagWithRows(tag: tag)
        }
        guard !each.isEmpty else { throw BatchError.emptyCopyRows }
        return each.enumerated().map { index, row in
            CopyAssignment.substituting(index + 1, into: defaults.merging(row) { _, own in own })
        }
    }

    /// One row's copy, as a `cp` line of its own.
    ///
    /// The revision guard rides the first copy only: the parent (or the document, at the
    /// root) has already changed by the second, so re-checking the same token would fail
    /// against the write this same line just made. `at` walks with the rows, so a list
    /// inserted at an index stays in row order.
    private static func oneCopy(
        of op: BatchOperation.CopyOp,
        root: [String: AnyCodable],
        offsetBy index: Int
    ) -> BatchOperation.CopyOp {
        var single = op
        single.each = nil
        single.tag = nil
        single.props = root.isEmpty ? nil : root
        single.at = op.at.map { $0 + index }
        single.rev = index == 0 ? op.rev : nil
        return single
    }

    // MARK: - Checked before anything is written

    /// Refuses any path-keyed property that names nothing inside the node being copied.
    ///
    /// Resolved against the source rather than the copy, which is what makes it a
    /// *pre*-flight: a deep copy carries the source's names, and an instance's
    /// descendants are the definition's, so a path that resolves in one resolves in the
    /// other. Only ``EditingError/addressNotFound(address:nearMisses:)`` is translated —
    /// an ambiguous path is a different mistake, and the resolver's own message lists
    /// the candidates for it.
    ///
    /// - Parameters:
    ///   - rows: The property maps the line will copy with.
    ///   - sourceID: The id of the node being copied.
    ///   - numbered: Whether a failure should name the row it came from — true for an
    ///     `each` list, false for the single copy that has no row number.
    ///   - parameters: The parameters the source publishes, so a published name is
    ///     checked as the path it stands for.
    ///   - document: The document the source lives in.
    /// - Throws: ``BatchError/copyPathNotInSource(row:key:source:)``, or
    ///   ``BatchError/parameterPathNotFound(name:path:component:)`` for a published
    ///   name whose own declaration has gone stale.
    private static func refuseUnknownPaths(
        in rows: [[String: AnyCodable]],
        copying sourceID: String,
        numbered: Bool,
        parameters: [ComponentParameter],
        in document: EditableDocument
    ) throws {
        let source = document.namePath(of: sourceID)
        let component = document.node(id: sourceID)?.common.name ?? sourceID
        for (index, row) in rows.enumerated() {
            for key in row.keys.sorted() {
                if let parameter = parameters.first(where: { $0.name == key }),
                   !parameter.collidesWithProperty, parameter.property == nil
                {
                    throw BatchError.parameterPathNotFound(
                        name: parameter.name, path: parameter.path, component: component
                    )
                }
                guard case let .descendant(path) = CopyAssignment
                    .destination(of: key, parameters: parameters).destination
                else { continue }
                let refusal = BatchError.copyPathNotInSource(
                    row: numbered ? index + 1 : nil, key: key, source: source
                )
                guard let address = CopyAssignment.address(inside: sourceID, path: path) else {
                    throw refusal
                }
                do {
                    _ = try document.resolve(address)
                } catch let error as EditingError {
                    guard case .addressNotFound = error else { throw error }
                    throw refusal
                }
            }
        }
    }
}
