//
//  DocumentLinter+TextStripped.swift
//  Woodcase
//

import Foundation

/// The `text-style-stripped` check.
///
/// Pen strips three things from a `text` node when it opens a file, and draws none of
/// them: its stroke (`stroke`, `strokeWidth`, `strokeAlignment`, `strokeLinecap`,
/// `strokeLinejoin`), `underline` and `strikethrough` — although all of them are in the
/// schema Pen publishes. Confirmed in Pen.app 1.2.14 and the headless `pen` CLI: the
/// keys are gone from the node Pen reports after load and from the file it saves, and
/// its export draws plain text (`project/2026-09-26-what-pen-drops-from-a-file.md`).
///
/// Woodcase keeps drawing an underline and a strikethrough, so for those two the
/// finding says the renders disagree; Woodcase draws no text stroke either, so that
/// one is simply lost. Each case is its own finding, so fixing one leaves the others
/// standing. `underline: false` and `strikethrough: false` lose nothing and are clean.
extension DocumentLinter {
    /// A text node's stroke, underline and strikethrough, one finding each.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)` — so an underline
    ///     held in a `$variable` is judged on the value it resolves to.
    /// - Returns: Up to three findings, in the order stroke, underline, strikethrough.
    static func textStyleStripped(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .text(data) = node.kind else { return [] }
        var found: [LintFinding] = []

        let strokeKeys = [
            data.stroke != nil ? "stroke" : nil,
            data.strokeWidth != nil ? "strokeWidth" : nil,
            data.strokeAlignment != nil ? "strokeAlignment" : nil,
            data.strokeLinecap != nil ? "strokeLinecap" : nil,
            data.strokeLinejoin != nil ? "strokeLinejoin" : nil,
        ].compactMap(\.self)
        if !strokeKeys.isEmpty {
            found.append(finding(
                .textStyleStripped, row,
                "carries \(strokeKeys.joined(separator: ", ")), but Pen strips a text node's stroke "
                    + "when it opens the file and draws none; Woodcase draws none either. Outline "
                    + "text some other way, or remove the keys."
            ))
        }
        for (key, value) in [("underline", data.underline), ("strikethrough", data.strikethrough)]
            where value?.literalValue == true
        {
            found.append(finding(
                .textStyleStripped, row,
                "sets \(key): true, but Pen strips `\(key)` from text when it opens the file and "
                    + "draws none. Woodcase draws it, so Woodcase's render and Pen's disagree."
            ))
        }
        return found
    }
}
