//
//  PenNode+TextDataSpans.swift
//  Woodcase
//

import Foundation

public extension PenNode.TextData {
    /// The runs that style this node's content: its ``spans``' runs when they were made for
    /// the literal content, and none when there are no spans, the spans are stale, or the
    /// content is an unresolved variable.
    ///
    /// Every consumer that sets the node's text — layout measurement, ink, the CG renderer,
    /// ``PenTextLayout/init(_:box:color:)`` — reads this, so a stale styling draws plain
    /// everywhere at once.
    var appliedRuns: [PenTextRun] {
        guard let spans, let content = content?.literalValue else { return [] }
        return spans.appliedRuns(to: content)
    }
}
