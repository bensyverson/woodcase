//
//  PenTextStyle+AttributedString.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    public extension PenTextStyle {
        /// What a built string is for, which decides the attributes beyond the font,
        /// kern, decorations and line pitch every build carries.
        enum Purpose {
            /// Laying the text out to draw it, or to find where its drawn ink lands: the
            /// glyphs take `color`, and each line is aligned horizontally. Color never
            /// changes geometry; Core Text's `CTLineDraw` reads it from the runs.
            case drawing(color: CGColor)

            /// Measuring the text's size for layout: no color, and no horizontal
            /// alignment. A frame justifies a justified paragraph's lines to the width
            /// it is given, so measuring with alignment could move a measured size (and
            /// the `.layout.json` fixtures with it); alignment only places lines within
            /// a size already measured.
            case sizing
        }

        /// The font this style sets, resolved through Core Text's registry and cached
        /// process-wide (`PenTextMeasurer.resolveFont(family:size:weight:style:)`).
        var font: CTFont {
            PenTextMeasurer.resolveFont(
                family: fontFamily,
                size: fontSize,
                weight: String(fontWeight),
                style: isItalic ? "italic" : "normal"
            )
        }

        /// Builds the Core Text string that sets `text` in this style, with its runs.
        ///
        /// This is the one builder for a text node's content: the CG renderer, text ink
        /// bounds and ``PenTextMeasurer/measure(_:fontFamily:fontSize:fontWeight:fontStyle:letterSpacing:lineHeight:maxWidth:runs:indents:)``
        /// all build through it, so the fonts, kern and line pitch that are drawn are the
        /// ones that were measured. Each stretch of ``segments(of:runs:)`` is set in its own
        /// resolved font and decorations, and, when drawn, in its run's fill or else
        /// `color`; a stretch with a fill of its own is marked with
        /// ``PenTextRenderer/runFillKey``. The paragraph — line pitch
        /// (``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)`` of this style),
        /// alignment and letter spacing — is this style's throughout. Strikethrough, which
        /// Core Text does not draw, is marked with ``PenTextRenderer/strikethroughKey``
        /// for ``PenTextRenderer/drawStrikethrough(lines:in:)``. Each paragraph an indent
        /// covers (``PenParagraphIndent``) takes its indents, and a tab stop at its head
        /// indent, on top of the same pitch and alignment. A run's
        /// ``PenTextRun/inlinePadding`` is laid out as extra advance on each side of it
        /// (``InlinePadding``).
        ///
        /// - Parameters:
        ///   - text: The string to set. An empty one builds an empty string.
        ///   - runs: Its styled runs, offsets in UTF-16 code units; none for plain text.
        ///   - indents: Its paragraphs' indents, offsets in UTF-16 code units; none for a
        ///     text whose lines all start at the left edge.
        ///   - purpose: Whether the string is drawn (with its color and alignment) or
        ///     only sized.
        /// - Returns: The string, with this style's font, pitch and first baseline.
        func attributedString(
            _ text: String, runs: [PenTextRun] = [], indents: [PenParagraphIndent] = [], for purpose: Purpose
        ) -> PenStyledText {
            let resolved = font
            let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: fontSize, font: resolved)
            let alignment: CTTextAlignment? = switch purpose {
            case .drawing: Self.coreTextAlignment(textAlign)
            case .sizing: nil
            }
            let paragraph = PenTextMeasurer.paragraphStyle(lineHeight: pitch, alignment: alignment)

            let string: CFAttributedString
            if runs.isEmpty, indents.isEmpty {
                var attributes = characterAttributes(font: resolved, fill: nil, for: purpose)
                attributes[kCTParagraphStyleAttributeName] = paragraph
                string = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
            } else {
                let mutable = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
                CFAttributedStringReplaceString(mutable, CFRange(location: 0, length: 0), text as CFString)
                for segment in segments(of: text, runs: runs) {
                    var attributes = segment.style.characterAttributes(
                        font: segment.style.font, fill: segment.fill, for: purpose
                    )
                    attributes[kCTParagraphStyleAttributeName] = paragraph
                    let range = CFRange(location: segment.range.lowerBound, length: segment.range.count)
                    CFAttributedStringSetAttributes(mutable, range, attributes as CFDictionary, true)
                }
                let length = text.utf16.count
                let padding = InlinePadding(text: text, runs: runs, letterSpacing: letterSpacing)
                for indent in padding.indents(merging: indents) {
                    let lower = min(max(indent.start, 0), length)
                    let upper = min(max(indent.end, lower), length)
                    guard lower < upper else { continue }
                    CFAttributedStringSetAttribute(
                        mutable, CFRange(location: lower, length: upper - lower), kCTParagraphStyleAttributeName,
                        PenTextMeasurer.paragraphStyle(lineHeight: pitch, alignment: alignment, indent: indent)
                    )
                }
                padding.applyKerns(to: mutable)
                string = mutable
            }
            return PenStyledText(
                string: string,
                font: resolved,
                pitch: pitch,
                firstBaseline: PenTextMeasurer.firstBaseline(of: resolved, lineHeight: lineHeight, pitch: pitch),
                lineHeight: lineHeight
            )
        }

        /// The attributes one stretch of characters in this style is set with: its font,
        /// kern and decorations, and when drawn its color.
        ///
        /// - Parameters:
        ///   - font: This style's resolved font.
        ///   - fill: A run's own color, or `nil` for the purpose's color.
        ///   - purpose: Whether the string is drawn or only sized.
        /// - Returns: The attributes, without the paragraph style.
        private func characterAttributes(font: CTFont, fill: PenHexColor?, for purpose: Purpose) -> [CFString: Any] {
            var attributes: [CFString: Any] = [kCTFontAttributeName: font]
            if let letterSpacing {
                attributes[kCTKernAttributeName] = letterSpacing as CFNumber
            }
            if underline {
                attributes[kCTUnderlineStyleAttributeName] = CTUnderlineStyle.single.rawValue as CFNumber
            }
            if strikethrough {
                attributes[PenTextRenderer.strikethroughKey] = true as CFBoolean
            }
            if case let .drawing(color) = purpose {
                attributes[kCTForegroundColorFromContextAttributeName] = false
                attributes[kCTForegroundColorAttributeName] = fill?.sRGBColor ?? color
                if fill != nil {
                    attributes[PenTextRenderer.runFillKey] = true as CFBoolean
                }
            }
            return attributes
        }

        /// The Core Text alignment a horizontal alignment sets lines at.
        ///
        /// - Parameter align: The style's alignment.
        /// - Returns: Its Core Text equivalent.
        private static func coreTextAlignment(_ align: PenTextAlign) -> CTTextAlignment {
            switch align {
            case .left: .left
            case .center: .center
            case .right: .right
            case .justify: .justified
            }
        }
    }
#endif
