//
//  PenPostIt+Chrome.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// The look's measures for one node: the style's numbers multiplied by the node's
    /// look scale (``PenNode/noteScale``), and the marks set in its body's lines by its
    /// type size over ``PenPostIt/defaultFontSize``.
    ///
    /// The look's size is the note's own stored factor, independent of its type size
    /// (Ben's ruling of 2026-10-20): the paper's radius, hairline and shadows, the padding,
    /// the author line and a card's chrome take ``scale``. A bullet and a checkbox's edge sit
    /// in the body's lines, sized to its letters as a checkbox's side is to their cap height,
    /// so they take ``typeScale``; a scale multiplies both.
    struct Chrome: Friendly {
        /// The look.
        let style: Style
        /// The node's look scale: what every measure of the look is multiplied by.
        let scale: Double
        /// The body's size over the default: what a body mark's size is multiplied by.
        let typeScale: Double

        /// Measures the look at a look scale, for a body set at `fontSize`.
        init(style: Style, scale: Double, fontSize: Double) {
            self.style = style
            self.scale = scale.isFinite && scale > 0 ? scale : 1
            typeScale = fontSize > 0 ? fontSize / PenPostIt.defaultFontSize : 1
        }

        /// Measures the look of a note, prompt or context, or `nil` for any other node.
        init?(of node: PenNode, style: Style) {
            guard let scale = node.noteScale, let text = node.noteTextStyle else { return nil }
            self.init(style: style, scale: scale, fontSize: text.fontSize)
        }

        /// The padding between the edges and the body, before the chrome adds to it:
        /// ``PenPostIt/textInsets`` at the look's scale.
        var insets: PenPadding.Edges {
            let base = PenPostIt.textInsets
            return PenPadding.Edges(
                top: base.top * scale, right: base.right * scale, bottom: base.bottom * scale, left: base.left * scale
            )
        }

        /// The paper's hairline width.
        var hairlineWidth: Double {
            style.hairlineWidth * scale
        }

        /// The paper's shadows.
        var shadows: [PenPostItExpansion.Shadow] {
            style.shadows.map { $0.scaled(by: scale) }
        }

        /// A label's size.
        var labelSize: Double {
            style.labelFontSize * scale
        }

        /// A label line's height.
        var labelLine: Double {
            labelSize * style.labelLineHeight
        }

        /// The space between the body and the author line.
        var footerGap: Double {
            style.footerGap * scale
        }

        /// The space between a card's sections.
        var sectionGap: Double {
            style.sectionGap * scale
        }

        /// A prompt's header row: as tall as its model chip.
        var chipHeight: Double {
            labelLine + 2 * style.chipPaddingY * scale
        }

        /// A context's header row: as tall as its ⓘ mark or its label, whichever is more.
        var contextHeader: Double {
            max(style.infoMarkDiameter * scale, labelLine)
        }

        /// The Run label's size.
        var runSize: Double {
            style.runFontSize * scale
        }

        /// A prompt's run row: as tall as its button.
        var runRow: Double {
            runSize * style.labelLineHeight + 2 * style.runPaddingY * scale
        }

        /// The style a chrome label is set in.
        func label(size: Double? = nil, weight: Double, tracking: Double? = nil) -> PenTextStyle {
            let size = size ?? labelSize
            return PenTextStyle(
                fontFamily: style.labelFontFamily, fontSize: size, fontWeight: weight,
                letterSpacing: tracking.map { $0 * size }, lineHeight: style.labelLineHeight
            )
        }

        /// The author a note's author line names: its `woodcase.author`, or `nil` when it
        /// names none (or an empty one), and the note has no author line.
        ///
        /// A note's `state` plays no part: only comments are open or resolved (Ben's
        /// ruling, 2026-10-11), and a comment is not drawn here.
        ///
        /// - Parameter metadata: The note's metadata.
        /// - Returns: The author, or `nil`.
        static func author(_ metadata: PenPostIt.Metadata?) -> String? {
            metadata?.author.flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}
