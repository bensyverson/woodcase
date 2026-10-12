//
//  PenPostIt+Style.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The rev 2 look's numbers: every color, radius and size a note, prompt or context is
    /// drawn with.
    ///
    /// Penumbra's notes design (`../Penumbra/project/2026-10-11-notes-comments-and-spans.md`,
    /// decision 12) and its mockup set them; ``standard`` is that look. The expansion
    /// (``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:body:)``) reads
    /// them, so a renderer never does: it draws the parts it is given. See
    /// <doc:PenPostItLook>.
    ///
    /// It holds no words: the chrome's labels are ``PenPostIt/Label``s, which the
    /// expansion's caller turns into strings, so an editor can localize them.
    ///
    /// Geometry is in points at a body size of ``PenPostIt/defaultFontSize``. The text of
    /// the chrome — the author line, a card's header, chip, status and Run — scales with
    /// the note's own font size, so resizing a note, which scales its text (spec §5.9), scales
    /// its chrome with it; the paper's radius, hairline and shadows do not.
    struct Style: Friendly {
        /// The rev 2 look.
        public static let standard = Style()

        /// Creates the rev 2 look; change a property to vary it.
        public init() {}

        // MARK: Paper

        /// A note's corner radius.
        public var noteCornerRadius: Double = 6
        /// A prompt's or context's corner radius.
        public var cardCornerRadius: Double = 8
        /// The hairline inside a note's and a prompt's edge: 6% black.
        public var hairline = PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x0F)
        /// A context's stronger hairline: 10% black, its only edge.
        public var contextHairline = PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x1A)
        /// The hairline's width.
        public var hairlineWidth: Double = 1
        /// The soft shadows a note and a prompt cast, nearest first.
        public var shadows: [PenPostItExpansion.Shadow] = [
            PenPostItExpansion.Shadow(
                offsetX: 0, offsetY: 1, blur: 3, color: PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x1A)
            ),
            PenPostItExpansion.Shadow(
                offsetX: 0, offsetY: 4, blur: 12, color: PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x14)
            ),
        ]
        /// A prompt's paper: white.
        public var promptPaper = PenHexColor(red: 0xFF, green: 0xFF, blue: 0xFF)
        /// A context's paper: a quiet off-white.
        public var contextPaper = PenHexColor(red: 0xF7, green: 0xF7, blue: 0xF5)

        // MARK: Ink

        /// The ink on paper brighter than ``darkPaperLuminance``: black at 86%, 55% and 38%.
        public var inkOnLight = Ink(
            primary: PenHexColor(red: 0, green: 0, blue: 0, alpha: 219),
            secondary: PenHexColor(red: 0, green: 0, blue: 0, alpha: 140),
            tertiary: PenHexColor(red: 0, green: 0, blue: 0, alpha: 97)
        )
        /// The ink on darker paper: white at 92%, 55% and 38%.
        public var inkOnDark = Ink(
            primary: PenHexColor(red: 255, green: 255, blue: 255, alpha: 235),
            secondary: PenHexColor(red: 255, green: 255, blue: 255, alpha: 140),
            tertiary: PenHexColor(red: 255, green: 255, blue: 255, alpha: 97)
        )
        /// The relative luminance at or below which paper takes ``inkOnDark``.
        public var darkPaperLuminance: Double = 0.36

        // MARK: Labels and the author line

        /// The family every chrome label is set in, whatever the body's.
        public var labelFontFamily: String = PenTextStyle.defaultFontFamily
        /// The author line's, header's, chip's and status's size.
        public var labelFontSize: Double = 11
        /// The labels' line height, as a multiple of their size.
        public var labelLineHeight: Double = 1.35
        /// The author name's weight.
        public var authorWeight: Double = 500
        /// The space between the body and the author line.
        public var footerGap: Double = 8
        /// The identity dot's diameter.
        public var identityDotDiameter: Double = 8
        /// The space between the identity dot and the name.
        public var identityDotGap: Double = 5
        /// The light ring an identity dot takes on paper that takes ``inkOnDark``, so a
        /// dark hue still reads: white at 80%.
        public var identityRingOnDark = PenHexColor(red: 0xFF, green: 0xFF, blue: 0xFF, alpha: 0xCC)
        /// The ring's width, inside the dot's edge.
        public var identityRingWidth: Double = 1

        // MARK: Body marks

        /// A list bullet's diameter: a dot that reads at 13 points, drawn in the body ink.
        public var bulletDiameter: Double = 5
        /// A checkbox's side, as a multiple of the body's cap height. The box is centered on
        /// the capitals' midline, so it lines up with the text at any size (Ben, 2026-10-11:
        /// a cap-height box read small).
        public var checkboxScale: Double = 1.17
        /// A checkbox's corner radius.
        public var checkboxCornerRadius: Double = 2.5
        /// The edge of an open checkbox.
        public var checkboxStroke: Double = 1.25
        /// The stroke of a done checkbox's check mark.
        public var checkMarkStroke: Double = 1.6

        // MARK: Cards

        /// A card's header weight.
        public var headerWeight: Double = 600
        /// A card's header tracking, as a fraction of its size.
        public var headerTracking: Double = 0.02
        /// The space between a card's header, body and run row.
        public var sectionGap: Double = 10
        /// The triangle before a prompt's header and the Run label, a space apart. U+FE0E
        /// keeps it a glyph, never an emoji.
        public var playGlyph = "\u{25B6}\u{FE0E}"
        /// The model chip's horizontal padding.
        public var chipPaddingX: Double = 7
        /// The model chip's vertical padding.
        public var chipPaddingY: Double = 2
        /// The model chip's fill: 6% black.
        public var chipFill = PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x0F)
        /// The model name's weight.
        public var chipWeight: Double = 500
        /// The Run label's size.
        public var runFontSize: Double = 12
        /// The Run label's weight.
        public var runWeight: Double = 600
        /// The Run button's horizontal padding.
        public var runPaddingX: Double = 11
        /// The Run button's vertical padding.
        public var runPaddingY: Double = 5
        /// The Run button's corner radius.
        public var runCornerRadius: Double = 7
        /// The Run button's fill.
        public var runButtonFill = PenHexColor(red: 0x1C, green: 0x1C, blue: 0x1E)
        /// The Run label's color.
        public var runButtonInk = PenHexColor(red: 0xFF, green: 0xFF, blue: 0xFF)
        /// The status dot's diameter, beside the status at the bottom left.
        public var statusDotDiameter: Double = 8
        /// The space between the status dot and its label.
        public var statusDotGap: Double = 5
        /// The ⓘ mark's diameter.
        public var infoMarkDiameter: Double = 16
        /// The ⓘ mark's ring width.
        public var infoMarkStroke: Double = 1.5
        /// The ⓘ mark's ring and glyph color: 45% black.
        public var infoMarkColor = PenHexColor(red: 0, green: 0, blue: 0, alpha: 0x73)
        /// The glyph inside the ⓘ mark: the information symbol's letter, not a word.
        public var infoGlyph = "i"
        /// The glyph's size.
        public var infoGlyphFontSize: Double = 10
        /// The glyph's weight.
        public var infoGlyphWeight: Double = 800
        /// The space between the ⓘ mark and the header.
        public var infoMarkGap: Double = 6
        /// The status dot colors, by run state: amber, blue, green.
        public var statusColors: [PenHexColor] = [
            PenHexColor(red: 0xF5, green: 0xA6, blue: 0x23),
            PenHexColor(red: 0x0A, green: 0x84, blue: 0xFF),
            PenHexColor(red: 0x34, green: 0xC7, blue: 0x59),
        ]

        /// The status dot's color for a run state.
        ///
        /// - Parameter state: Where the prompt's run stands.
        /// - Returns: Its color, from ``statusColors`` in ``RunState`` order.
        public func statusColor(_ state: RunState) -> PenHexColor {
            let index = RunState.allCases.firstIndex(of: state) ?? 0
            return statusColors.indices.contains(index) ? statusColors[index] : inkOnLight.secondary
        }
    }
}
