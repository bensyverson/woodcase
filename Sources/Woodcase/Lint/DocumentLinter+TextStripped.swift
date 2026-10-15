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
/// An underline and a strikethrough on a text of literal content are protected: Woodcase
/// keeps them in `metadata.woodcase.textDecoration` too, which Pen keeps, and restores
/// them on its next read and write (``PenTextDecoration``, leaf kyrTTL). So for those two
/// the finding is a notice that Pen's own render shows neither while Woodcase's shows
/// both. A protection made for older words counts: it restores and is made again for the
/// new ones. One Woodcase cannot protect — content held in a variable — is still a warning
/// that a save in Pen loses it. Woodcase draws no
/// text stroke, so that one is simply lost. Each case is its own finding, so fixing one
/// leaves the others standing. `underline: false` and `strikethrough: false` lose
/// nothing and are clean.
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
        // Protection for older words still protects: it is made again for these on the
        // next read or write. Content in a variable has none to make.
        let protection = data.content?.literalValue == nil ? nil : node.textDecoration
        let key = PenMetadata.WoodcaseKey.textDecoration
        for (name, value, isProtected) in [
            ("underline", data.underline, protection?.underline == true),
            ("strikethrough", data.strikethrough, protection?.strikethrough == true),
        ] where value?.literalValue == true {
            if isProtected {
                found.append(LintFinding(
                    check: .textStyleStripped, severity: .notice, nodeID: row.id, path: row.address,
                    message: "sets \(name): true, which Pen strips from text when it opens the file and draws none. "
                        + "It is protected: Woodcase keeps it in metadata.\(PenMetadata.woodcaseNamespace)."
                        + "\(key.rawValue), which Pen keeps, and restores it when it next reads the file, so only "
                        + "Pen's own render goes without it."
                ))
            } else {
                found.append(finding(
                    .textStyleStripped, row,
                    "sets \(name): true, but Pen strips `\(name)` from text when it opens the file and "
                        + "draws none, and it is not protected: Woodcase protects it in metadata only on text "
                        + "whose content is plain, not a variable. A save in Pen loses it."
                ))
            }
        }
        return found
    }
}
