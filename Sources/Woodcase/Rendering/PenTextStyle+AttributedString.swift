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

        /// Builds the Core Text string that sets `text` in this style.
        ///
        /// This is the one builder for a text node's content: the CG renderer, text ink
        /// bounds and ``PenTextMeasurer/measure(_:fontFamily:fontSize:fontWeight:fontStyle:letterSpacing:lineHeight:maxWidth:)``
        /// all build through it, so the font, kern and line pitch that are drawn are the
        /// ones that were measured. Every line is set at one pitch,
        /// ``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)``; strikethrough, which
        /// Core Text does not draw, is marked with ``PenTextRenderer/strikethroughKey``
        /// for ``PenTextRenderer/drawStrikethrough(lines:in:)``.
        ///
        /// - Parameters:
        ///   - text: The string to set. An empty one builds an empty string.
        ///   - purpose: Whether the string is drawn (with its color and alignment) or
        ///     only sized.
        /// - Returns: The string, with its font, pitch and first baseline.
        func attributedString(_ text: String, for purpose: Purpose) -> PenStyledText {
            let resolved = font
            var attributes: [CFString: Any] = [kCTFontAttributeName: resolved]
            if let letterSpacing {
                attributes[kCTKernAttributeName] = letterSpacing as CFNumber
            }
            if underline {
                attributes[kCTUnderlineStyleAttributeName] = CTUnderlineStyle.single.rawValue as CFNumber
            }
            if strikethrough {
                attributes[PenTextRenderer.strikethroughKey] = true as CFBoolean
            }

            let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: fontSize, font: resolved)
            let alignment: CTTextAlignment?
            switch purpose {
            case let .drawing(color):
                attributes[kCTForegroundColorFromContextAttributeName] = false
                attributes[kCTForegroundColorAttributeName] = color
                alignment = Self.coreTextAlignment(textAlign)
            case .sizing:
                alignment = nil
            }
            attributes[kCTParagraphStyleAttributeName] = PenTextMeasurer.paragraphStyle(
                lineHeight: pitch, alignment: alignment
            )

            let string = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
            return PenStyledText(
                string: string,
                font: resolved,
                pitch: pitch,
                firstBaseline: PenTextMeasurer.firstBaseline(of: resolved, lineHeight: lineHeight, pitch: pitch)
            )
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
