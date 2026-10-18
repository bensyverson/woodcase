//
//  EditPlanner+DefaultTextStyle.swift
//  Woodcase
//

import Foundation

/// Use as Default Text Style: the document's default text style is a text marked with
/// ``PenMetadata/WoodcaseKey/defaultTextStyle``, followed live, since `.pen` has no
/// document-level metadata (Penumbra spec §6.3, Ben's ruling of 2026-10-18).
///
/// Each write folds one key onto the metadata the node already carries
/// (``NodePropertyCodec/folding(_:onto:)``), so every other metadata key is kept, and an
/// unmark removes the key rather than writing `false`.
public extension EditPlanner {
    /// Plans Use as Default Text Style: marks one text as the document's default and
    /// removes the mark from every other text that holds it.
    ///
    /// The edits are plain property writes, to submit as one edit — one undo step. A text
    /// already marked is not written again, so marking the only marked text plans nothing.
    ///
    /// Refused for a node that is not a text (``EditRefusal/Code/notAText``), inside a
    /// component instance (``EditRefusal/Code/insideInstance``), and for an id naming
    /// nothing (``EditRefusal/Code/addressNotFound``).
    ///
    /// - Parameters:
    ///   - nodeID: The text: a stored id, or the expanded id an editor holds.
    ///   - document: The document, as it stands.
    /// - Returns: The edits, to submit as one; empty when the text is already the only
    ///   marked one.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planMarkDefaultTextStyle(
        nodeID: String,
        in document: EditableDocument
    ) throws(EditRefusal) -> [EditOperation] {
        let target = try restructuredID(nodeID, in: document)
        guard let node = document.node(id: target), case .text = node.kind else {
            throw EditRefusal(
                code: .notAText,
                address: nodeID,
                message: "\(nodeID) is not a text, so it cannot be the default text style."
            )
        }
        var operations = defaultTextStyleMarks(in: document)
            .filter { $0 != target }
            .compactMap { defaultTextStyleWrite(.null, on: $0, in: document) }
        if !isDefaultTextStyleMarked(node), let mark = defaultTextStyleWrite(.bool(true), on: target, in: document) {
            operations.append(mark)
        }
        return operations
    }

    /// Plans removing the default text style: takes the mark off every text that holds
    /// it, so the document has no default until another text is marked.
    ///
    /// An editor plans this when Use as Default Text Style is chosen on the current
    /// default. Every mark goes, not only the first's, so a second mark left by a merge
    /// or a paste does not quietly become the default in its place.
    ///
    /// - Parameter document: The document, as it stands.
    /// - Returns: The edits, to submit as one; empty when no text is marked.
    static func planUnmarkDefaultTextStyle(in document: EditableDocument) -> [EditOperation] {
        defaultTextStyleMarks(in: document).compactMap { defaultTextStyleWrite(.null, on: $0, in: document) }
    }

    // MARK: - Private

    /// Every text holding the mark, in document order.
    private static func defaultTextStyleMarks(in document: EditableDocument) -> [String] {
        document.nodeIDsInDocumentOrder().filter { id in
            document.node(id: id).map(isDefaultTextStyleMarked) ?? false
        }
    }

    /// Whether a node is a text holding the mark.
    private static func isDefaultTextStyleMarked(_ node: PenNode) -> Bool {
        guard case .text = node.kind else { return false }
        return node.common.metadata?[woodcase: .defaultTextStyle] == .bool(true)
    }

    /// The write that sets the key on one node, folded onto the metadata it carries; `nil`
    /// for a node the store does not hold.
    private static func defaultTextStyleWrite(
        _ value: AnyCodable,
        on id: String,
        in document: EditableDocument
    ) -> EditOperation? {
        guard let node = document.node(id: id),
              let properties = try? NodePropertyCodec.folding(
                  [PenMetadata.WoodcaseKey.defaultTextStyle.path: value], onto: node
              )
        else { return nil }
        return .setProperties(EditOperation.SetProperties(nodeID: id, properties: properties))
    }
}
