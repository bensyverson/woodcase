//
//  PenTextLayout.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    /// A text set in its style and placed in its box: the one layout call every consumer of
    /// a text's lines shares.
    ///
    /// Woodcase's CG renderer draws a text node through it, ``PenLayoutEngine`` measures the
    /// node's ink through it, RapidPro's rasterizer draws through it, and an editor reads
    /// its caret, hit-testing and selection from its ``geometry`` — so the line a caret sits
    /// on is the line that was drawn, to the point. It builds the string once
    /// (``PenTextStyle/attributedString(_:for:)``), breaks it once (``PenTextLines``), and
    /// decides once where the block of lines sits in the box (``blockTop``).
    ///
    /// Coordinates are the box's own: origin at its top-left, y growing downward, except
    /// ``placed``, which is Core Text's y-up space for `CTLineDraw`; ``textSpace`` maps one to
    /// the other. A block taller than its box is not clipped: it overflows (``overflows``),
    /// and its lines and carets lie past the box.
    ///
    /// Not ``Friendly``: it holds Core Text objects, which neither encode nor cross actors,
    /// and lives for one draw or one edit. Its ``geometry`` is the `Sendable`, `Codable`
    /// value to keep.
    public struct PenTextLayout {
        /// The color a layout's glyphs take when none is given: opaque black. Color never
        /// changes geometry, so a layout built only to measure or to place a caret can use it.
        public static let defaultColor = CGColor(gray: 0, alpha: 1)

        /// The text that was set.
        public let text: String

        /// The style it was set in.
        public let style: PenTextStyle

        /// The box it was placed in, in points.
        public let box: CGSize

        /// The styled string, with its resolved font, pitch and first baseline.
        public let styled: PenStyledText

        /// The lines Core Text broke the text into at the box's width.
        public let lines: PenTextLines

        /// The top of the block of lines, in points below the box's top: 0 for top
        /// alignment, centered for middle, flush with the bottom for bottom. Negative when a
        /// block taller than its box is centered or bottom-aligned, as Pen draws it.
        public let blockTop: CGFloat

        /// Sets `text` in `style` and places it in a box of `box`.
        ///
        /// An empty text sets no lines; it draws nothing and has no ink, though its
        /// ``geometry`` still has a line for the caret.
        ///
        /// - Parameters:
        ///   - text: The text to set.
        ///   - style: Its style.
        ///   - box: The box it is placed in: the wrapping width, and the height vertical
        ///     alignment is measured against.
        ///   - color: The glyphs' color, which `CTLineDraw` reads from the runs.
        public init(text: String, style: PenTextStyle, box: CGSize, color: CGColor = defaultColor) {
            self.text = text
            self.style = style
            self.box = box
            let styled = style.attributedString(text, for: .drawing(color: color))
            self.styled = styled
            lines = PenTextLines(
                styled.string, width: box.width, pitch: styled.pitch, firstBaseline: styled.firstBaseline
            )
            blockTop = Self.blockTop(
                ofHeight: ceil(lines.height), inBoxOfHeight: box.height, alignment: style.textAlignVertical
            )
        }

        /// Sets a text node's content in its style and places it in its box.
        ///
        /// - Parameters:
        ///   - data: The text node's data.
        ///   - box: The node's box size.
        ///   - color: The glyphs' color.
        /// - Returns: The layout, or `nil` when the content is absent or an unresolved
        ///   variable reference — there is no text to set.
        public init?(_ data: PenNode.TextData, box: CGSize, color: CGColor = defaultColor) {
            guard let text = data.content?.literalValue else { return nil }
            self.init(text: text, style: PenTextStyle(data), box: box, color: color)
        }

        /// The styled Core Text string.
        public var attributedString: CFAttributedString {
            styled.string
        }

        /// The resolved font the text is set in.
        public var font: CTFont {
            styled.font
        }

        /// The block's height: the line count times the pitch, rounded up to a whole point,
        /// the height vertical alignment centers.
        public var blockHeight: CGFloat {
            ceil(lines.height)
        }

        /// The block of lines in the box's y-down space: the box's width, from
        /// ``blockTop``, ``blockHeight`` tall.
        public var blockRect: CGRect {
            CGRect(x: 0, y: blockTop, width: box.width, height: blockHeight)
        }

        /// Whether the block is taller than the box, so lines reach past it.
        public var overflows: Bool {
            blockHeight > box.height
        }

        /// Each line with its baseline origin in Core Text's y-up space over the box: draw a
        /// line by setting its origin as the context's text position under ``textSpace``.
        public var placed: [(CTLine, CGPoint)] {
            lines.placed(inBoxOfHeight: box.height)
        }

        /// The map from ``placed``'s y-up space into the box's y-down space, with the
        /// block's vertical offset: concatenate it onto a y-down context before drawing.
        public var textSpace: CGAffineTransform {
            CGAffineTransform(translationX: 0, y: blockTop + box.height).scaledBy(x: 1, y: -1)
        }

        /// The tight bounds of the glyphs' outlines, in the box's y-down space, or `nil`
        /// when no line has ink.
        ///
        /// The union of each glyph's outline, as Pen measures its text's fill path; not
        /// confined to the box, since an unbreakable word, an italic's slant or a tight line
        /// height draws past it. Computed on each read: it walks every glyph.
        public var inkBounds: CGRect? {
            var union: CGRect?
            let space = textSpace
            for (line, origin) in placed {
                guard var bounds = PenLayoutEngine.outlineBounds(of: line) else { continue }
                bounds.origin.x += origin.x
                bounds.origin.y += origin.y
                let transformed = bounds.applying(space)
                union = union.map { $0.union(transformed) } ?? transformed
            }
            return union
        }

        /// Where the top of a block of lines sits down a box, by vertical alignment — the one
        /// copy of that rule.
        ///
        /// - Parameters:
        ///   - blockHeight: The block's height, rounded up to a whole point.
        ///   - boxHeight: The box's height.
        ///   - alignment: The vertical alignment.
        /// - Returns: The block's top, in points below the box's top.
        static func blockTop(
            ofHeight blockHeight: CGFloat, inBoxOfHeight boxHeight: CGFloat, alignment: PenTextAlignVertical
        ) -> CGFloat {
            switch alignment {
            case .top: 0
            case .middle: (boxHeight - blockHeight) / 2
            case .bottom: boxHeight - blockHeight
            }
        }
    }
#endif
