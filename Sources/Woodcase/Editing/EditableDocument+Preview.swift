//
//  EditableDocument+Preview.swift
//  Woodcase
//

import Foundation

/// Previewing property edits: what a commit would store, computed without one.
///
/// An editor shows a gesture in progress — a value scrubbed, a stop dragged, a number
/// being typed — on its own canvas before the gesture ends, without sending each step
/// to collaborators, the undo stack or the file. It plans the gesture's edits as it
/// would commit them (``EditPlanner``), asks ``previewNodes(for:)`` for the nodes they
/// would leave, and draws ``materializeSnapshot(overlaying:isolation:)`` with them. The
/// patch and override logic is the commit's own, so the preview and the commit cannot
/// disagree.
public extension EditableDocument {
    /// Why ``previewNodes(for:)`` cannot preview an operation.
    enum PreviewError: Error, Friendly {
        /// The operation is not one that patches a stored node's properties: a
        /// structural, variable, import, theme or document-level edit. Its payload is
        /// the operation's case name, such as `deleteNode`.
        case notAPropertyEdit(String)
    }

    /// The stored nodes `operations` would leave, by id, computed without applying them.
    ///
    /// Each node is what ``apply(_:)`` would store: children stripped, as in ``nodes``.
    /// Operations apply in order, so two that touch one node fold onto it as a commit
    /// folds them; each is checked against the document as it stands, exactly as
    /// applying it checks it. Nothing changes: not the store, the caches, the dirty
    /// tracking nor the CRDT.
    ///
    /// Only the operations ``EditPlanner`` plans are property edits:
    /// ``EditOperation/setProperties(_:)``, ``EditOperation/overrideDescendant(_:)``
    /// and ``EditOperation/overrideRoot(_:)``.
    ///
    /// - Parameter operations: The operations to preview.
    /// - Returns: Each node the operations write — an override writes its instance's
    ///   `ref` node — as a commit would store it.
    /// - Throws: ``PreviewError/notAPropertyEdit(_:)`` for any other operation, or the
    ///   ``EditingError`` applying the operation would throw.
    func previewNodes(for operations: [EditOperation]) throws -> [String: PenNode] {
        var preview: [String: PenNode] = [:]
        for operation in operations {
            switch operation {
            case let .setProperties(op):
                var node = try validateSetProperties(op, onto: preview[op.nodeID]).new
                node.kind = node.kind.withEmptyChildren()
                preview[op.nodeID] = node
            case let .overrideDescendant(op):
                preview[op.refNodeID] = try overriddenNode(for: op, onto: preview[op.refNodeID])
            case let .overrideRoot(op):
                preview[op.refNodeID] = try overriddenNode(for: op, onto: preview[op.refNodeID])
            default:
                throw PreviewError.notAPropertyEdit(Self.caseName(of: operation))
            }
        }
        return preview
    }

    /// The case name of an operation, such as `deleteNode`.
    private static func caseName(of operation: EditOperation) -> String {
        Mirror(reflecting: operation).children.first?.label ?? String(describing: operation)
    }
}
