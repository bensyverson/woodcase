//
//  DocumentLinter+CollapsedAbsoluteFrame.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/collapsedAbsoluteFrame`` check.
///
/// A `layout: "none"` frame places its children at their own `x`/`y`; it has no flow for
/// `fit_content` to measure. Pen settles such a frame's `fit_content` axis at its
/// fallback — 0 when it has none — and never around its children, and it re-saves a
/// missing width or height as `fit_content(0)` (the Pen probe on leaf `Jg0BOv`,
/// `render-sizeless-frames.pen`). Woodcase settles it the same way
/// (`PenLayoutEngine.AbsoluteLayout`). The children still draw, overhanging the point,
/// but the frame's own fill has no area, `clip` hides every child, and in a flex parent
/// the frame takes no room, so its next sibling lands on top of its children.
///
/// Nothing is wrong with the file as Pen reads it, which is why this is a warning: an
/// author who wrote a sizeless absolute frame almost always meant it to wrap its
/// children, and this check says so before the fill, the clip or the flow surprises them.
/// A frame with no children is ``LintCheck/emptyFitContent``'s case, not this one.
extension DocumentLinter {
    /// A `layout: "none"` frame with children whose width or height settles at 0 because
    /// it is `fit_content` with no fallback, or a fallback of 0.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: Zero or one finding, naming every axis that collapses. A fallback other
    ///   than 0 is clean — the author chose the size — and so is a flex frame, which
    ///   measures its children, and a group, which takes their union.
    static func collapsedAbsoluteFrame(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        // The row counts the children: the node as it renders comes from the flat store,
        // which strips them.
        guard case let .frame(data) = node.kind, data.layout == PenLayoutDirection.none, row.childCount > 0
        else { return [] }

        var axes: [String] = []
        if collapsesToZero(PenLayoutEngine.widthSizing(of: node)) { axes.append("width") }
        if collapsesToZero(PenLayoutEngine.heightSizing(of: node)) { axes.append("height") }
        guard !axes.isEmpty else { return [] }

        let settles = axes.count > 1 ? "at 0×0" : axes[0] == "width" ? "to 0pt wide" : "to 0pt tall"
        let sets = axes.map { "kind.\($0)=<value>" }.joined(separator: " ")
        return [finding(
            .collapsedAbsoluteFrame, row,
            "is layout:none with no \(axes.joined(separator: " or ")), so it settles \(settles), as Pen "
                + "settles it: fit_content on an absolute frame is its fallback, not its children's union. "
                + "Its children still draw, but its fill is invisible, clip hides its children, and it "
                + "takes no space in a flow. Give it a size: "
                + "`woodcase set <file> \(row.id) \(sets)`."
        )]
    }

    /// Whether a sizing is `fit_content` that settles at 0 on an absolute frame: no
    /// fallback, or a fallback of 0.
    ///
    /// - Parameter sizing: The sizing mode to test.
    /// - Returns: Whether the axis collapses.
    private static func collapsesToZero(_ sizing: PenSizing) -> Bool {
        if case let .fitContent(fallback) = sizing { return (fallback ?? 0) == 0 }
        return false
    }
}
