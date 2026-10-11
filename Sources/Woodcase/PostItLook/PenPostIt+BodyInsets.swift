//
//  PenPostIt+BodyInsets.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The space between a note's, prompt's or context's edges and its body text: the
    /// ``textInsets``, plus the chrome above or below the text.
    ///
    /// A note with an author, or resolved, adds its author line to the bottom inset; a
    /// prompt adds its header row to the top and its run row to the bottom; a context adds
    /// its header row to the top. The chrome scales with the node's font size. The layout
    /// grows a node by its text plus these insets (Penumbra's notes design, decision 4), and
    /// the expansion sets the body in the box they leave, so the two agree on where the
    /// text ends and the author line begins.
    ///
    /// - Parameters:
    ///   - node: Any node.
    ///   - style: The look whose chrome is measured.
    /// - Returns: The insets, or `nil` for a node that is not a note, prompt or context.
    static func bodyInsets(of node: PenNode, style: Style = .standard) -> PenPadding.Edges? {
        guard let variant = Variant(node.kind), let text = node.noteTextStyle else { return nil }
        let chrome = Chrome(style: style, fontSize: text.fontSize)
        let base = textInsets
        switch variant {
        case .note:
            let footer = Chrome.Footer(PenPostIt.Metadata(node)) == nil ? 0 : chrome.footerGap + chrome.labelLine
            return PenPadding.Edges(top: base.top, right: base.right, bottom: base.bottom + footer, left: base.left)
        case .prompt:
            return PenPadding.Edges(
                top: base.top + chrome.chipHeight + chrome.sectionGap, right: base.right,
                bottom: base.bottom + chrome.runRow + chrome.sectionGap, left: base.left
            )
        case .context:
            return PenPadding.Edges(
                top: base.top + chrome.contextHeader + chrome.sectionGap, right: base.right,
                bottom: base.bottom, left: base.left
            )
        }
    }

    /// Where a note's, prompt's or context's body text is set: its box less its
    /// ``bodyInsets(of:style:)``, in its own coordinates.
    ///
    /// - Parameters:
    ///   - node: The note, prompt or context.
    ///   - width: Its laid-out width.
    ///   - height: Its laid-out height.
    ///   - style: The look whose chrome is measured.
    /// - Returns: The text's frame, never narrower or shorter than zero; for any other
    ///   node, the box less ``textInsets``.
    static func textFrame(of node: PenNode, width: Double, height: Double, style: Style = .standard) -> PenRect {
        let insets = bodyInsets(of: node, style: style) ?? textInsets
        return PenRect(
            x: insets.left,
            y: insets.top,
            width: max(0, width - insets.horizontal),
            height: max(0, height - insets.vertical)
        )
    }
}
