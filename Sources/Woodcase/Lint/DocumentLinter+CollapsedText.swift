//
//  DocumentLinter+CollapsedText.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/collapsedText`` check.
///
/// A text node whose box settles at zero on an axis draws almost nothing on that axis —
/// a sliver of a glyph, or nothing at all — and no other check catches it: `text-overflow`
/// only asks about height, and skips a zero-width box outright because there is no wrap
/// width to measure against (see `DocumentLinter+TextOverflow.swift`). This check is that
/// skip's complement.
///
/// The collapse has one mechanism, in `PenLayoutEngine.layoutLeafNode`. A leaf's width is
/// resolved once, up front, from `kind.width` alone
/// (`resolveIntrinsicSize(props.widthSizing, …)`); text measurement only *overrides* that
/// resolution when `textGrowth` says the axis should follow the text —
/// `needsWidthFromText` requires `textGrowth != .fixedWidth`, and the whole measurement
/// step is skipped for `fixed-width-height`, which never measures either axis. So a
/// `fixed-width` node's `kind.width` is never replaced by a measurement, and a
/// `fixed-width-height` node's `kind.width` and `kind.height` never are. Left as
/// `fit_content` — a sizing mode that means "measure the content" — with no numeric
/// fallback, `resolveIntrinsicSize` has nothing to resolve it to but 0
/// (`.fitContent(fallback: nil)` resolves to `fallback ?? 0`). The text is real, the box
/// is not: the renderer composes into a frame with no room, and what shows is whatever
/// fits in nothing.
///
/// This is the same shape of bug ``DocumentLinter/fillContainerInFitParent(_:node:parent:in:)``
/// and ``DocumentLinter/emptyFitContent(_:node:)`` report — a sizing mode the engine
/// cannot resolve because nothing gives it a fallback — applied to text growth instead of
/// to a container's children.
extension DocumentLinter {
    /// A text node whose settled width or height is zero while its content is not.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: Zero or one finding, naming every axis that collapsed. Empty text and
    ///   a `fit_content` axis that carries a numeric fallback are both clean, and so is
    ///   `auto` growth, which always lets both axes measure from the text.
    static func collapsedText(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .text(data) = node.kind,
              let content = data.content?.literalValue, !content.isEmpty
        else { return [] }

        let growth = data.textGrowth ?? .auto
        guard growth != .auto else { return [] }

        var axes: [String] = []
        if bareFitContent(PenLayoutEngine.widthSizing(of: node)) {
            axes.append("width")
        }
        if growth == .fixedWidthHeight, bareFitContent(PenLayoutEngine.heightSizing(of: node)) {
            axes.append("height")
        }
        guard !axes.isEmpty else { return [] }

        let axisWord = axes.joined(separator: " and ")
        let pairs = axes.map { "kind.\($0)=fit_content" }.joined(separator: " and ")
        let have = axes.count > 1 ? "have" : "has"
        let mechanism = growth == .fixedWidth
            ? "kind.textGrowth=\(growth.rawValue) holds its width to kind.width, and \(pairs) \(have) "
            + "nothing to fall back on"
            : "kind.textGrowth=\(growth.rawValue) never measures the text, so \(pairs) \(have) "
            + "nothing to fall back on"
        let settles = axes.count > 1 ? "on \(axisWord)" : axes[0] == "width" ? "wide" : "tall"
        let numericSets = axes.map { "kind.\($0)=<value>" }.joined(separator: " ")

        return [finding(
            .collapsedText, row,
            "settles to 0pt \(settles) because \(mechanism), so the layout engine resolves it "
                + "to 0 instead of measuring the text. Run "
                + "`woodcase set <file> \(row.id) \(numericSets)` with a number, or "
                + "`woodcase set <file> \(row.id) kind.textGrowth=\(PenTextGrowth.auto.rawValue)` "
                + "to let \(axisWord) follow the text."
        )]
    }

    /// Whether a sizing fits its content with no fallback for the layout engine to use.
    ///
    /// Not the same helper as `DocumentLinter.swift`'s private `bareFitContent` —
    /// duplicated here rather than widened to `internal`, the way `boxCannotGrow` is
    /// duplicated in `DocumentLinter+TextOverflow.swift`, so each check's file stays
    /// self-contained.
    ///
    /// - Parameter sizing: The sizing mode to test.
    /// - Returns: Whether it is `fit_content` with no fallback value.
    private static func bareFitContent(_ sizing: PenSizing) -> Bool {
        if case let .fitContent(fallback) = sizing { return fallback == nil }
        return false
    }
}
