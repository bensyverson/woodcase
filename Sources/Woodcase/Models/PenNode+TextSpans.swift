//
//  PenNode+TextSpans.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The rich text this node's metadata holds for it (``PenMetadata/textSpans``), or `nil`
    /// for a node that is not a `text`, has none, or holds spans that cannot be read.
    var textSpans: PenTextSpans? {
        guard case .text = kind else { return nil }
        return common.metadata?.textSpans
    }

    /// The runs that style this text node's content: its spans' runs while they were made
    /// for its literal content, and none otherwise — no spans, stale spans, an unresolved
    /// variable, or a node that is not a `text`.
    ///
    /// Every consumer that sets a node's text — layout measurement, ink, the CG renderer,
    /// ``PenTextLayout/init(_:box:color:)``, the overflow lint — reads this, so stale
    /// styling draws plain everywhere at once.
    var appliedRuns: [PenTextRun] {
        guard case let .text(data) = kind, let content = data.content?.literalValue, let spans = textSpans
        else { return [] }
        return spans.appliedRuns(to: content)
    }

    /// Whether this text node holds spans made for other content than its own literal
    /// content, so they are ignored (``PenTextSpans/isStale(for:)``).
    var hasStaleTextSpans: Bool {
        guard case let .text(data) = kind, let content = data.content?.literalValue, let spans = textSpans
        else { return false }
        return spans.isStale(for: content)
    }
}
