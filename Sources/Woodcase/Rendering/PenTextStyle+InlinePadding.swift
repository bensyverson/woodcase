//
//  PenTextStyle+InlinePadding.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreText
    import Foundation

    extension PenTextStyle {
        /// The extra advance a text's padded runs (``PenTextRun/inlinePadding``) take, as
        /// Core Text sets it: CSS's inline padding, in the one string every layout, measure
        /// and draw is built from.
        ///
        /// Core Text has no space *before* a glyph, only kern *after* one, so:
        ///
        /// - the padding after a run is kern on the run's last grapheme;
        /// - the padding before it is kern on the grapheme before it — the space before a
        ///   mention keeps its own width and the run starts `padding` later;
        /// - at a paragraph's start there is no grapheme before it, so the paragraph's
        ///   first-line indent grows by the padding instead: the run's text starts that far
        ///   in from the text column.
        ///
        /// A run that starts a line *wrapped* from the line before gets no padding before
        /// it: the grapheme that carries it is the space that ended the previous line, and
        /// Core Text hangs trailing white space. A renderer drawing a pill there keeps the
        /// pill's left edge on the text column.
        struct InlinePadding {
            /// The extra kern to add, by UTF-16 range of one grapheme.
            private(set) var kerns: [Range<Int>: Double] = [:]
            /// The extra first-line indent to add, by the UTF-16 offset a paragraph starts at,
            /// with the offset just past that paragraph.
            private(set) var paragraphStarts: [Int: (padding: Double, end: Int)] = [:]
            /// The kern every character already takes: the style's letter spacing.
            let letterSpacing: Double?

            /// Gathers the padding of every run that has some.
            ///
            /// - Parameters:
            ///   - text: The text.
            ///   - runs: Its runs; only those with a positive ``PenTextRun/inlinePadding``
            ///     count, each widened to grapheme boundaries as ``segments(of:runs:)`` widens it.
            ///   - letterSpacing: The style's letter spacing, which the kern adds to.
            init(text: String, runs: [PenTextRun], letterSpacing: Double?) {
                self.letterSpacing = letterSpacing
                let padded = runs.filter { ($0.inlinePadding ?? 0) > 0 }
                guard !padded.isEmpty else { return }
                let units = Array(text.utf16)
                let length = units.count
                let graphemes = text.graphemeBoundariesInUTF16
                for run in padded {
                    let padding = run.inlinePadding ?? 0
                    let lower = graphemes.last { $0 <= min(max(run.start, 0), length) } ?? 0
                    let upper = graphemes.first { $0 >= min(max(run.end, 0), length) } ?? length
                    guard lower < upper else { continue }
                    let last = graphemes.last { $0 < upper } ?? lower
                    kerns[last ..< upper, default: 0] += padding
                    if lower == 0 || Self.separators.contains(units[lower - 1]) {
                        let end = units[lower...].firstIndex { Self.separators.contains($0) }.map { $0 + 1 } ?? length
                        paragraphStarts[lower, default: (0, end)].padding += padding
                    } else {
                        let before = graphemes.last { $0 < lower } ?? 0
                        kerns[before ..< lower, default: 0] += padding
                    }
                }
            }

            /// The UTF-16 units Core Text ends a paragraph at.
            private static let separators: Set<UInt16> = [0x0A, 0x0D, 0x85, 0x2029]

            /// The text's paragraph indents with each padded paragraph start's first-line
            /// indent grown, and a new indent for a padded paragraph that had none.
            ///
            /// - Parameter indents: The text's own paragraph indents.
            /// - Returns: The indents to set.
            func indents(merging indents: [PenParagraphIndent]) -> [PenParagraphIndent] {
                guard !paragraphStarts.isEmpty else { return indents }
                var merged = indents
                for (start, paragraph) in paragraphStarts.sorted(by: { $0.key < $1.key }) {
                    if let index = merged.firstIndex(where: { $0.range.contains(start) }) {
                        merged[index].firstLineIndent += paragraph.padding
                    } else {
                        merged.append(PenParagraphIndent(
                            start: start, end: paragraph.end, firstLineIndent: paragraph.padding, headIndent: 0
                        ))
                    }
                }
                return merged
            }

            /// Sets the kerns on the string, each over the style's letter spacing.
            ///
            /// - Parameter string: The string, its characters already attributed.
            func applyKerns(to string: CFMutableAttributedString) {
                for (range, padding) in kerns {
                    let kern = (letterSpacing ?? 0) + padding
                    CFAttributedStringSetAttribute(
                        string, CFRange(location: range.lowerBound, length: range.count), kCTKernAttributeName,
                        kern as CFNumber
                    )
                }
            }
        }
    }
#endif
