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
        /// Each line's band is one pitch tall from ``blockTop``, its baseline where it is
        /// drawn, and its carets at Core Text's caret offsets
        /// (`CTLineEnumerateCaretOffsets`, which follows clusters and bidi), kept only at
        /// grapheme-cluster boundaries. Built on each read; keep the value rather than the
        /// layout.
        var geometry: PenTextGeometry {
            let boundaries = Self.graphemeBoundaries(of: text)
            let pitch = Double(lines.pitch)
            var built: [PenTextGeometry.Line] = []
            for (index, line) in lines.lines.enumerated() {
                let bandTop = Double(blockTop) + Double(index) * pitch
                built.append(geometryLine(
                    line, start: Double(lines.lineStarts[index]), bandTop: bandTop, boundaries: boundaries
                ))
            }
            let length = text.utf16.count
            if built.isEmpty {
                // Pen sets an empty text as one line, so the caret sits where that line would.
                let top = Self.blockTop(
                    ofHeight: ceil(lines.pitch), inBoxOfHeight: box.height, alignment: style.textAlignVertical
                )
                built.append(emptyLine(at: 0, bandTop: Double(top)))
            } else if let last = built.last, last.ending == .hardBreak {
                built.append(emptyLine(at: length, bandTop: last.band.y + pitch))
            }
            return PenTextGeometry(
                box: PenSize(width: Double(box.width), height: Double(box.height)), length: length, lines: built
            )
        }

        /// One Core Text line as geometry.
        private func geometryLine(
            _ line: CTLine, start: Double, bandTop: Double, boundaries: [Int]
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
            let pitch = Double(lines.pitch)
            return PenTextGeometry.Line(
                stringRange: lower ..< upper,
                baseline: bandTop + Double(lines.firstBaseline),
                band: PenRect(x: 0, y: bandTop, width: Double(box.width), height: pitch),
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

        /// The UTF-16 offset of every grapheme-cluster boundary in `text`, 0 and its length
        /// included.
        private static func graphemeBoundaries(of text: String) -> [Int] {
            var offset = 0
            var boundaries = [0]
            for character in text {
                offset += character.utf16.count
                boundaries.append(offset)
            }
            return boundaries
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
