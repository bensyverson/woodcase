//
//  DocumentLinter+SpansStale.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/spansStale`` check.
///
/// A text node's spans record the content they were made for (``PenTextSpans/text``). When
/// the content no longer equals it — Pen, which keeps metadata but has no rich text, edited
/// the words; or a write changed `content` without restating the spans — the runs are
/// ignored and the text draws plain rather than styling the wrong characters
/// (<doc:PenRichText>). The finding says so and names both ways out.
extension DocumentLinter {
    /// A text node, as it renders, whose spans were made for other content.
    ///
    /// A row inside an instance is skipped: its spans are the component's, reported once on
    /// the component's own node. An instance that overrides the text's content draws it
    /// plain by design — the spans were made for the component's words.
    ///
    /// - Parameters:
    ///   - row: The row, for the finding's id and path.
    ///   - node: The node as it renders, its content resolved.
    /// - Returns: Zero or one finding.
    static func spansStale(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator), let message = spansStaleMessage(node, id: row.id)
        else { return [] }
        return [finding(.spansStale, row, message)]
    }

    /// The ``LintCheck/spansStale`` finding for one stored node, or `nil` when its spans
    /// apply or it has none.
    ///
    /// A write that changes a text's content reports this when the write made the spans
    /// stale, in exactly the form `lint` prints, so the two are recognizably one fact.
    ///
    /// - Parameters:
    ///   - nodeID: The node's id, as stored.
    ///   - document: The document.
    /// - Returns: The finding, or `nil`.
    public static func spansStaleFinding(nodeID: String, in document: EditableDocument) -> LintFinding? {
        guard let node = document.node(id: nodeID), let message = spansStaleMessage(node, id: nodeID)
        else { return nil }
        return LintFinding(check: .spansStale, nodeID: nodeID, path: document.namePath(of: nodeID), message: message)
    }

    /// What the finding says about a node, or `nil` when its spans are not stale.
    private static func spansStaleMessage(_ node: PenNode, id: String) -> String? {
        guard node.hasStaleTextSpans, let spans = node.textSpans else { return nil }
        let runs = spans.runs.count == 1 ? "1 styled run" : "\(spans.runs.count) styled runs"
        let key = PenMetadata.WoodcaseKey.spans.path
        return "has \(runs) made for \"\(spans.text)\", not its content, so it draws plain. Restate "
            + "`\(key)` for the new words, or remove it with `woodcase set <file> \(id) \(key)=null`."
    }
}
