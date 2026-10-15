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
    /// for its literal content; once its words change, only those that covered the whole
    /// text, stretched over the new words (``PenTextSpans/appliedRuns(to:)``); and none for
    /// no spans, an unresolved variable, or a node that is not a `text`.
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
    /// content with runs that are ignored for it (``PenTextSpans/ignoredRuns(for:)``).
    ///
    /// Spans whose every run covered the whole text are not: they are stretched over the
    /// new words, so nothing is lost.
    var hasStaleTextSpans: Bool {
        guard case let .text(data) = kind, let content = data.content?.literalValue, let spans = textSpans
        else { return false }
        return !spans.ignoredRuns(for: content).isEmpty
    }
}
