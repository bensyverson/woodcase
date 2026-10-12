//
//  PenTextLayout+Geometry.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    public extension PenTextLayout {
        /// The layout's carets, lines and selection bands, as a plain value
        /// (``PenTextGeometry``).
        ///
        /// Each line's band is its ``PenTextLines/bands`` entry below ``blockTop`` — one
        /// pitch tall for a line in the node's face alone — its baseline where it is drawn,
        /// and its carets at Core Text's caret offsets
        /// (`CTLineEnumerateCaretOffsets`, which follows clusters and bidi), kept only at
        /// grapheme-cluster boundaries. Built on each read; keep the value rather than the
        /// layout.
        var geometry: PenTextGeometry {
            let boundaries = text.graphemeBoundariesInUTF16
            var built: [PenTextGeometry.Line] = []
            for (index, line) in lines.lines.enumerated() {
                built.append(geometryLine(
                    line, start: Double(lines.lineStarts[index]), band: lines.bands[index], boundaries: boundaries
                ))
            }
            let length = text.utf16.count
            if built.isEmpty {
                // Pen sets an empty text as one line, so the caret sits where that line would.
                let top = Self.blockTop(
                    ofHeight: ceil(lines.pitch), inBoxOfHeight: box.height, alignment: style.textAlignVertical
                )
                built.append(emptyLine(at: 0, bandTop: Double(top)))
            } else if let last = built.last, last.ending == .hardBreak, let line = lines.lines.last {
                let spacing = Double(PenTextLines.paragraphSpacing(after: line, in: attributedString))
                built.append(emptyLine(at: length, bandTop: last.band.y + last.band.height + spacing))
            }
            return PenTextGeometry(
                box: PenSize(width: Double(box.width), height: Double(box.height)), length: length, lines: built
            )
        }

        /// One Core Text line as geometry.
        private func geometryLine(
            _ line: CTLine, start: Double, band: PenTextLines.Band, boundaries: [Int]
        ) -> PenTextGeometry.Line {
            let range = CTLineGetStringRange(line)
            let lower = range.location, upper = range.location + range.length
            let lastGrapheme = boundaries.last { $0 < upper } ?? lower
            let ending: PenTextGeometry.Line.Ending = if upper > lower, Self.isNewline(text, from: lastGrapheme, to: upper) {
                .hardBreak
            } else if upper >= text.utf16.count {
                .endOfText
            } else {
                .softWrap
            }
            let lastStop = ending == .hardBreak ? lastGrapheme : upper

            var leading: [Int: Double] = [:]
            CTLineEnumerateCaretOffsets(line) { offset, characterIndex, leadingEdge, _ in
                if leadingEdge, leading[characterIndex] == nil {
                    leading[characterIndex] = offset
                }
            }
            let carets = boundaries.filter { $0 >= lower && $0 <= lastStop }.map { stop in
                let offset = stop < upper ? leading[stop] : nil
                let x = offset ?? Double(CTLineGetOffsetForStringIndex(line, stop, nil))
                return PenTextGeometry.Line.Caret(index: stop, x: start + x)
            }
            return PenTextGeometry.Line(
                stringRange: lower ..< upper,
                baseline: Double(blockTop + band.baseline),
                band: PenRect(x: 0, y: Double(blockTop + band.top), width: Double(box.width), height: Double(band.height)),
                start: start,
                trailingWhitespaceWidth: Double(CTLineGetTrailingWhitespaceWidth(line)),
                ending: ending,
                carets: carets.isEmpty ? [PenTextGeometry.Line.Caret(index: lower, x: start)] : carets
            )
        }

        /// A synthesized empty line holding one caret at `index`, placed by alignment.
        private func emptyLine(at index: Int, bandTop: Double) -> PenTextGeometry.Line {
            let width = Double(box.width)
            let x: Double = switch style.textAlign {
            case .left, .justify: 0
            case .center: width / 2
            case .right: width
            }
            return PenTextGeometry.Line(
                stringRange: index ..< index,
                baseline: bandTop + Double(lines.firstBaseline),
                band: PenRect(x: 0, y: bandTop, width: width, height: Double(lines.pitch)),
                start: x,
                trailingWhitespaceWidth: 0,
                ending: .endOfText,
                carets: [PenTextGeometry.Line.Caret(index: index, x: x)]
            )
        }

        /// Whether the UTF-16 span `lower..<upper` of `text` is one newline grapheme.
        private static func isNewline(_ text: String, from lower: Int, to upper: Int) -> Bool {
            let utf16 = text.utf16
            let start = utf16.index(utf16.startIndex, offsetBy: lower)
            let end = utf16.index(utf16.startIndex, offsetBy: upper)
            return text[start ..< end].first?.isNewline == true
        }
    }
#endif
