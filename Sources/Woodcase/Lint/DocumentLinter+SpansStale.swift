//
//  DocumentLinter+SpansStale.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/spansStale`` check.
///
/// A text node's spans record the content they were made for (``PenTextSpans/text``). When
/// the content no longer equals it — Pen, which keeps metadata but has no rich text, edited
/// the words; or a write changed `content` without restating the spans — the runs over part
/// of the text are ignored rather than styling the wrong characters, and only a run over
/// the whole text is stretched over the new words (<doc:PenRichText>). The finding counts
/// the runs ignored, so spans whose every run covered the whole text raise none, and names
/// both ways out.
extension DocumentLinter {
    /// A text node, as it renders, whose spans were made for other content; on an
    /// instance's row, each text inside it whose own spans did.
    ///
    /// An instance stores the spans it gives a text inside it in that text's override,
    /// `descendants[<key>].metadata.woodcase.spans` (Penumbra spec §7.6 (1)). When they no
    /// longer fit the content the instance shows, they are stale as a plain text's would be,
    /// and are reported against the text inside the instance — its expanded id, and the
    /// instance's path followed by the text's name. A text showing the component's spans is
    /// not: they are reported once on the component's own node, and an instance that
    /// overrides the text's content draws them plain by design, since they were made for the
    /// component's words. A row inside an instance (`tree --expand`) is skipped for the same
    /// reason; the instance's row reports what it stores.
    ///
    /// - Parameters:
    ///   - row: The row, for the finding's id and path.
    ///   - node: The node as it renders, its content resolved.
    ///   - context: The lint context, for the instance's stored overrides and their texts as
    ///     they render.
    /// - Returns: The findings.
    static func spansStale(_ row: TreeRow, node: PenNode, in context: Context) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator) else { return [] }
        var found = spansStaleMessage(node, id: row.id, remedy: .set).map { [finding(.spansStale, row, $0)] } ?? []
        guard let instance = context.authored(row), case let .ref(data) = instance.kind else { return found }
        for key in (data.descendants ?? [:]).keys.sorted() where overridesSpans(data.descendants?[key]) {
            let id = "\(row.id)\(NodeAddress.separator)\(key)"
            guard let shown = context.settled.nodes[id], let message = spansStaleMessage(shown, id: id, remedy: .override)
            else { continue }
            let name = shown.common.name ?? key
            found.append(LintFinding(
                check: .spansStale, nodeID: id, path: "\(row.address)\(NodeAddress.separator)\(name)", message: message
            ))
        }
        return found
    }

    /// Whether a `descendants` entry gives its text spans of its own.
    private static func overridesSpans(_ override: PenDescendantOverride?) -> Bool {
        guard case let .dictionary(metadata)? = override?.properties["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace],
              let spans = keys[PenMetadata.WoodcaseKey.spans.rawValue]
        else { return false }
        return spans != .null
    }

    /// Which write the finding's remedy names: a node's own `set`, or an instance's `override`.
    private enum Remedy {
        case set, override
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
        guard let node = document.node(id: nodeID), let message = spansStaleMessage(node, id: nodeID, remedy: .set)
        else { return nil }
        return LintFinding(check: .spansStale, nodeID: nodeID, path: document.namePath(of: nodeID), message: message)
    }

    /// The ``LintCheck/spansStale`` finding for a text inside an instance whose own spans —
    /// its override's — no longer fit the content the instance shows, or `nil` when they
    /// fit, or the instance gives it none.
    ///
    /// An `override` that changes the words reports this when it made the spans stale, as a
    /// `set` reports ``spansStaleFinding(nodeID:in:)``.
    ///
    /// - Parameters:
    ///   - refID: The instance's `ref` node.
    ///   - descendantKey: The text's key in the instance's `descendants`.
    ///   - document: The document.
    /// - Returns: The finding, or `nil`.
    public static func spansStaleFinding(
        instance refID: String, descendantKey: String, in document: EditableDocument
    ) -> LintFinding? {
        guard case let .ref(data)? = document.node(id: refID)?.kind, overridesSpans(data.descendants?[descendantKey]),
              let shown = EditPlanner.PlacedNode(descendant: descendantKey, ofInstance: refID, in: document)?.node
        else { return nil }
        let id = "\(refID)\(NodeAddress.separator)\(descendantKey)"
        guard let message = spansStaleMessage(shown, id: id, remedy: .override) else { return nil }
        return LintFinding(
            check: .spansStale, nodeID: id, path: document.namePath(ofDescendant: descendantKey, in: refID), message: message
        )
    }

    /// What the finding says about a node, or `nil` when its spans are not stale.
    private static func spansStaleMessage(_ node: PenNode, id: String, remedy: Remedy) -> String? {
        guard node.hasStaleTextSpans, let spans = node.textSpans else { return nil }
        let ignored = spans.runs.count - node.appliedRuns.count
        let runs = ignored == 1 ? "1 styled run" : "\(ignored) styled runs"
        let outcome = node.appliedRuns.isEmpty
            ? "so it draws plain"
            : "so they are ignored; only the runs over the whole text still apply"
        let key = PenMetadata.WoodcaseKey.spans.propertyPath
        let removal = switch remedy {
        case .set: "remove it with `woodcase set <file> \(id) \(key)=null`"
        case .override: "remove the instance's own with `woodcase override <file> \(id) --unset \(key)`"
        }
        return "has \(runs) made for \"\(spans.text)\", not its content, \(outcome). Restate "
            + "`\(key)` for the new words, or \(removal)."
    }
}
