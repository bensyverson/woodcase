//
//  PenPostIt+Chrome.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// The chrome's measures at one font size: the style's numbers scaled by the body's size
    /// over ``PenPostIt/defaultFontSize``.
    struct Chrome: Friendly {
        /// The look.
        let style: Style
        /// The body's size over the default: what every chrome measure is multiplied by.
        let scale: Double

        /// Measures the chrome for a body set at `fontSize`.
        init(style: Style, fontSize: Double) {
            self.style = style
            scale = fontSize > 0 ? fontSize / PenPostIt.defaultFontSize : 1
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

        /// What a note's author line shows: its author, whether it is resolved, or both.
        struct Footer: Friendly {
            /// The author, when the note names one.
            let author: String?
            /// Whether the note is resolved.
            let isResolved: Bool

            /// The footer a note's metadata asks for, or `nil` when it has neither an author
            /// nor a resolved state.
            init?(_ metadata: PenPostIt.Metadata?) {
                let author = metadata?.author.flatMap { $0.isEmpty ? nil : $0 }
                let isResolved = metadata?.state == .valid(.resolved)
                guard author != nil || isResolved else { return nil }
                self.author = author
                self.isResolved = isResolved
            }
        }
    }
}
