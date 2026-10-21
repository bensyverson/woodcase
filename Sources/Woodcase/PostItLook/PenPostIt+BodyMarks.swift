//
//  PenPostIt+BodyMarks.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    extension PenPostIt {
        /// The marks a body draws as shapes, placed on the lines its text is set in.
        ///
        /// The body is set once here with ``PenTextLayout`` — the layout every renderer and an
        /// editor's caret use — and each mark is placed from its geometry, so the marks sit on
        /// the lines that are drawn. None changes the text: a pill lies behind its mention and
        /// the padding the mention's run lays out, and a bullet or a box over its
        /// ``PenNoteMarkdown/markerPlaceholder``.
        ///
        /// - A **mention pill** per line the mention sits on, over the run and the
        ///   ``PenTextRun/inlinePadding`` laid out on each side of it, as tall as the body
        ///   font's ascent and descent around the line's baseline, fully rounded.
        /// - A **bullet**: a ``Style/bulletDiameter`` dot in the primary ink, centered on the
        ///   x-height, on the axis a checkbox would have.
        /// - A **checkbox**: a square ``Style/checkboxScale`` times the body's cap height on a side, centered on the capitals' midline
        ///   at the item's indent; a done one is filled in the secondary ink and carries a
        ///   ``PenPostItExpansion/Role/checkMark`` cut in the paper's color, an open one is only
        ///   edged.
        ///
        /// - Parameters:
        ///   - markdown: The body's markdown.
        ///   - text: The body's text paint.
        ///   - frame: The body's frame, in the node's coordinates.
        ///   - mentions: The mentions, with their colors.
        ///   - ink: The inks.
        ///   - paper: The paper's color.
        ///   - chrome: The look's measures, whose type scale (``Chrome/typeScale``) the marks'
        ///     sizes take: they sit in the body's lines, so they follow its letters.
        /// - Returns: The parts, in paint order, and the checkboxes with their hit rects.
        static func bodyMarks(
            of markdown: PenNoteMarkdown, text: PenPostItExpansion.Text, frame: PenRect,
            mentions: [PenPostItExpansion.Mention], ink: Ink, paper: PenHexColor, chrome: Chrome
        ) -> (parts: [PenPostItExpansion.Part], checkboxes: [PenPostItExpansion.Checkbox]) {
            guard !mentions.isEmpty || !markdown.bulletDisplayOffsets.isEmpty || !markdown.checklistItems.isEmpty
            else { return ([], []) }
            let layout = PenTextLayout(
                text: text.string, style: text.style, runs: text.runs, indents: text.indents,
                box: CGSize(width: frame.width, height: frame.height)
            )
            let metrics = Metrics(layout: layout, frame: frame)
            let style = chrome.style
            var parts = mentions.flatMap { mention in
                let run = text.runs.first { $0.mention != nil && $0.range == mention.range }
                return mentionPills(mention, padding: run?.inlinePadding ?? 0, metrics: metrics)
            }
            let diameter = style.bulletDiameter * chrome.typeScale
            for offset in markdown.bulletDisplayOffsets {
                guard let line = metrics.line(containing: offset) else { continue }
                let x = metrics.x(of: offset, on: line) + (metrics.capHeight - diameter) / 2
                let y = metrics.baseline(of: line) - metrics.xHeight / 2 - diameter / 2
                parts.append(PenPostItExpansion.Part(
                    role: .bullet, frame: PenRect(x: x, y: y, width: diameter, height: diameter),
                    paint: .shape(PenPostItExpansion.Shape(form: .ellipse, fill: ink.primary))
                ))
            }
            var checkboxes: [PenPostItExpansion.Checkbox] = []
            for item in markdown.checklistItems {
                guard let line = metrics.line(containing: item.boxDisplayRange.lowerBound) else { continue }
                let side = metrics.capHeight * style.checkboxScale
                let box = PenRect(
                    x: metrics.x(of: item.boxDisplayRange.lowerBound, on: line),
                    y: metrics.baseline(of: line) - (metrics.capHeight + side) / 2, width: side, height: side
                )
                checkboxes.append(PenPostItExpansion.Checkbox(item: item, frame: box))
                parts += checkboxParts(box, isChecked: item.isChecked, ink: ink, paper: paper, chrome: chrome)
            }
            return (parts, checkboxes)
        }

        /// A mention's pills, one per line it sits on.
        ///
        /// The padding is the mention run's own ``PenTextRun/inlinePadding``, already laid out
        /// as kern: the last glyph's advance carries the padding after, and the run's first
        /// glyph starts the padding after what precedes it, so the pill reaches back by the
        /// padding from there. Glyph positions, not carets: Core Text puts a caret in the
        /// middle of a kerned gap. Where
        /// the mention starts a line wrapped from the one before, no padding was laid out on
        /// its left (``PenTextStyle/InlinePadding``), and the pill starts at the caret, on
        /// the text column.
        private static func mentionPills(
            _ mention: PenPostItExpansion.Mention, padding: Double, metrics: Metrics
        ) -> [PenPostItExpansion.Part] {
            let lines = metrics.geometry.lines
            return lines.indices.compactMap { index in
                let line = lines[index]
                let lower = max(mention.range.lowerBound, line.stringRange.lowerBound)
                let upper = min(mention.range.upperBound, line.stringRange.upperBound)
                guard lower < upper else { return nil }
                let wrapped = lower == line.stringRange.lowerBound && index > 0 && lines[index - 1].ending == .softWrap
                let reach = lower == mention.range.lowerBound && !wrapped ? padding : 0
                let glyphs = metrics.glyphSpan(of: lower ..< upper, on: line)
                let start = glyphs.start - reach
                let end = glyphs.end
                let height = metrics.ascent + metrics.descent
                let pill = PenRect(x: start, y: metrics.baseline(of: line) - metrics.ascent, width: end - start, height: height)
                return PenPostItExpansion.Part(
                    role: .mentionPill, frame: pill,
                    paint: .shape(PenPostItExpansion.Shape(form: .roundedRect(cornerRadius: height / 2), fill: mention.color))
                )
            }
        }

        /// A checkbox's box, and its check mark when it is done.
        private static func checkboxParts(
            _ box: PenRect, isChecked: Bool, ink: Ink, paper: PenHexColor, chrome: Chrome
        ) -> [PenPostItExpansion.Part] {
            let style = chrome.style
            let form = PenPostItExpansion.Shape.Form.roundedRect(cornerRadius: style.checkboxCornerRadius * chrome.typeScale)
            guard isChecked else {
                let edge = PenPostItExpansion.Hairline(color: ink.secondary, width: style.checkboxStroke * chrome.typeScale)
                return [PenPostItExpansion.Part(
                    role: .checkbox, frame: box, paint: .shape(PenPostItExpansion.Shape(form: form, fill: nil, hairline: edge))
                )]
            }
            let stroke = PenPostItExpansion.Hairline(color: paper, width: style.checkMarkStroke * chrome.typeScale)
            return [
                PenPostItExpansion.Part(
                    role: .checkbox, frame: box, paint: .shape(PenPostItExpansion.Shape(form: form, fill: ink.secondary))
                ),
                PenPostItExpansion.Part(
                    role: .checkMark, frame: box,
                    paint: .shape(PenPostItExpansion.Shape(form: .checkMark, fill: nil, hairline: stroke))
                ),
            ]
        }

        /// A body's layout, its font's metrics, and where its frame sits in the node.
        private struct Metrics {
            /// The body's lines and carets.
            let geometry: PenTextGeometry
            /// The body's frame in the node.
            let frame: PenRect
            /// The body font's cap height.
            let capHeight: Double
            /// The body font's x-height.
            let xHeight: Double
            /// The body font's ascent.
            let ascent: Double
            /// The body font's descent.
            let descent: Double
            /// Where each UTF-16 offset's glyphs start and end, in the node: the start of its
            /// first glyph, and the end of its last one's advance, kern included.
            let glyphs: [Int: (start: Double, end: Double)]

            init(layout: PenTextLayout, frame: PenRect) {
                geometry = layout.geometry
                self.frame = frame
                var glyphs: [Int: (start: Double, end: Double)] = [:]
                for (line, lineStart) in zip(layout.lines.lines, layout.lines.lineStarts) {
                    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                        let count = CTRunGetGlyphCount(run)
                        var positions = [CGPoint](repeating: .zero, count: count)
                        var advances = [CGSize](repeating: .zero, count: count)
                        var indices = [CFIndex](repeating: 0, count: count)
                        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                        CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                        for glyph in 0 ..< count {
                            let start = frame.x + Double(lineStart + positions[glyph].x)
                            let end = start + Double(advances[glyph].width)
                            let known = glyphs[indices[glyph]]
                            glyphs[indices[glyph]] = (min(known?.start ?? start, start), max(known?.end ?? end, end))
                        }
                    }
                }
                self.glyphs = glyphs
                capHeight = Double(CTFontGetCapHeight(layout.font))
                xHeight = Double(CTFontGetXHeight(layout.font))
                ascent = Double(CTFontGetAscent(layout.font))
                descent = Double(CTFontGetDescent(layout.font))
            }

            /// The line a UTF-16 offset is set on.
            func line(containing index: Int) -> PenTextGeometry.Line? {
                geometry.lines.first { $0.stringRange.contains(index) }
            }

            /// The x, in the node, of the caret before a UTF-16 offset on a line.
            func x(of index: Int, on line: PenTextGeometry.Line) -> Double {
                frame.x + (line.carets.first { $0.index == index }?.x ?? line.start)
            }

            /// Where the glyphs of the UTF-16 offsets in a range start and end, in the node; on
            /// a line, its caret at the range's ends where a glyph is missing.
            func glyphSpan(of range: Range<Int>, on line: PenTextGeometry.Line) -> (start: Double, end: Double) {
                let spans = range.compactMap { glyphs[$0] }
                return (
                    spans.map(\.start).min() ?? x(of: range.lowerBound, on: line),
                    spans.map(\.end).max() ?? x(of: range.upperBound, on: line)
                )
            }

            /// A line's baseline, in the node.
            func baseline(of line: PenTextGeometry.Line) -> Double {
                frame.y + line.baseline
            }
        }
    }
#else
    import Foundation

    extension PenPostIt {
        /// Without Core Text there is no layout to place the marks on, so a body draws none.
        static func bodyMarks(
            of _: PenNoteMarkdown, text _: PenPostItExpansion.Text, frame _: PenRect,
            mentions _: [PenPostItExpansion.Mention], ink _: Ink, paper _: PenHexColor, chrome _: Chrome
        ) -> (parts: [PenPostItExpansion.Part], checkboxes: [PenPostItExpansion.Checkbox]) {
            ([], [])
        }
    }
#endif
