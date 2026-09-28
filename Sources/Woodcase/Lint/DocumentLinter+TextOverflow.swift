//
//  DocumentLinter+TextOverflow.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/textOverflow`` check.
///
/// A text box whose height cannot grow is the one place in the format where content
/// disappears without a trace. Two halves of the pipeline agree to it: the layout
/// engine skips text measurement entirely for a `fixed-width-height` node
/// (`PenLayoutEngine.layoutLeafNode`), so the box keeps the size the file declares
/// however much text is in it; and the renderer lays the text into a frame of exactly
/// that height (`PenTextRenderer`), where Core Text composes **whole lines** and
/// simply stops when the next one would not fit. The overflow is therefore not clipped
/// — a half-line the reader can see and diagnose — it is absent, and a screenshot of
/// the design looks like a design that says less than it does.
///
/// The check re-measures the settled text at the settled width, with the same
/// ``PenLayoutEngine/defaultTextMeasurer`` the layout used, and reports the difference.
///
/// ## Only height
///
/// Width alone can never overflow, because the renderer wraps at the box width: a
/// `fixed-width` node's text rewraps to fit and pushes the height instead. So there is
/// exactly one question to ask — is the box tall enough for the text at the width it
/// actually has — and both a declared `kind.height` and a `fill_container` height
/// settled by a parent are answered by it.
///
/// A zero-width box is skipped: there is no wrap width to measure against, and the
/// answer would be an arbitrarily large number rather than a useful one.
extension DocumentLinter {
    /// A text node in a box shorter than its content needs.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id, path and settled
    ///     rect.
    ///   - node: The node as it renders — see `Context.resolved(_:)`, so `fontSize`
    ///     and the rest are literals rather than `$variable` references.
    /// - Returns: Zero or one finding. Empty text, a box that fits, a zero-width box
    ///   and a height that sizes to content are all clean.
    static func textOverflow(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .text(data) = node.kind,
              let content = data.content?.literalValue, !content.isEmpty,
              let rect = row.rect, rect.width > 0,
              boxCannotGrow(data, node: node)
        else { return [] }

        let needed = PenLayoutEngine.defaultTextMeasurer(
            content,
            data.fontFamily?.literalValue,
            data.fontSize?.literalValue,
            data.fontWeight?.literalValue,
            data.fontStyle?.literalValue,
            data.letterSpacing?.literalValue,
            data.lineHeight?.literalValue,
            rect.width
        ).height

        let overflow = needed - rect.height
        guard overflow > TreeRow.clipTolerance else { return [] }

        let fits = number(needed.rounded(.up))
        let grow = data.textGrowth == .fixedWidthHeight
            ? "kind.height=fit_content kind.textGrowth=\(PenTextGrowth.fixedWidth.rawValue)"
            : "kind.height=fit_content"
        return [LintFinding(
            check: .textOverflow,
            nodeID: row.id,
            path: row.address,
            message: "needs \(fits)pt of height for its text at \(number(rect.width))pt wide, but "
                + "its box is \(number(rect.height))pt tall and cannot grow: \(number(overflow.rounded(.up)))pt "
                + "of text falls outside it. A renderer composes whole lines and drops the ones "
                + "past the bottom edge, so the overflow does not show at all. Run "
                + "`woodcase set <file> \(row.id) kind.height=\(fits)` for a box that fits, or "
                + "`woodcase set <file> \(row.id) \(grow)` to let it grow with its content."
        )]
    }

    /// Whether the node's height is one the text cannot push.
    ///
    /// Two ways in, and the layout engine draws the line at both: a
    /// `fixed-width-height` growth skips measurement altogether, so even a
    /// `fit_content` height stays at whatever it resolves to with nothing measured;
    /// and any height that is not `fit_content` — a number, a `fill_container` a
    /// parent settles — is the file's answer rather than the text's.
    ///
    /// - Parameters:
    ///   - data: The text node's data.
    ///   - node: The node itself, so the height sizing comes from the layout engine
    ///     (defaults included) rather than from the raw property.
    /// - Returns: Whether the box height is fixed against its content.
    private static func boxCannotGrow(_ data: PenNode.TextData, node: PenNode) -> Bool {
        data.textGrowth == .fixedWidthHeight || !PenLayoutEngine.heightSizing(of: node).isFitContent
    }
}
