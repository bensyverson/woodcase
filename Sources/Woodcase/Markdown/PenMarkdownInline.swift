//
//  PenMarkdownInline.swift
//  Woodcase
//

import Foundation

/// Parses one line's inline markdown: `**bold**`, `*italic*`/`_italic_`, `@mentions`,
/// backslash escapes, and code spans kept whole as written.
///
/// Emphasis follows CommonMark's delimiter-run rules (flanking, intraword `_`, the rule
/// of three) with its "process emphasis" matching, so `***both***`, `**a *b* c**` and
/// `snake_case` read as they do on GitHub. Anything it does not match stays as written.
struct PenMarkdownInline {
    /// One piece of a line, in order.
    enum Token {
        /// Text shown as written.
        case text(Range<Int>)
        /// A backslash and the punctuation it escapes; the backslash is removed.
        case escape(Range<Int>)
        /// A run of `*` or `_`: the index of its ``Delimiter``.
        case delimiter(Int)
        /// `@name`, shown as written: its range, and the name.
        case mention(Range<Int>, name: String)
    }

    /// A run of `*` or `_` that may open or close emphasis.
    struct Delimiter {
        /// The run's source range.
        let range: Range<Int>
        /// The character it is made of.
        let character: UInt16
        /// Whether it may open emphasis.
        let canOpen: Bool
        /// Whether it may close emphasis.
        let canClose: Bool
        /// How many of its characters are still unmatched.
        var remaining: Int
        /// How many of its leftmost characters close emphasis, and are hidden.
        var closing = 0
        /// How many of its rightmost characters open emphasis, and are hidden.
        var opening = 0
        /// Whether it can still be matched: a match deactivates those it encloses.
        var isActive = true
        /// The display offset where its shown characters, if any, start and end.
        var display = 0 ..< 0
    }

    /// A matched pair: the opener's and the closer's indices, and whether it is strong.
    struct Emphasis {
        let opener: Int
        let closer: Int
        let isStrong: Bool
    }

    /// The line's source range, its newline excluded.
    let range: Range<Int>

    /// Whether the line is already bold (a heading), which a mention keeps.
    let isBold: Bool

    /// Parses the line and writes its display text and runs.
    ///
    /// - Parameter output: The parse's output.
    func parse(into output: inout PenMarkdownOutput) {
        let tokens: [Token]
        var delimiters: [Delimiter]
        (tokens, delimiters) = tokenize(output.source)
        let pairs = Self.match(&delimiters)
        var mentions: [(display: Range<Int>, name: String)] = []
        for token in tokens {
            switch token {
            case let .text(range):
                output.keep(range)
            case let .escape(range):
                output.replace(range.lowerBound ..< range.lowerBound + 1, with: "")
                output.keep(range.lowerBound + 1 ..< range.upperBound)
            case let .mention(range, name):
                let start = output.offset
                output.keep(range)
                mentions.append((start ..< output.offset, name))
            case let .delimiter(index):
                let run = delimiters[index]
                let shown = run.range.lowerBound + run.closing ..< run.range.upperBound - run.opening
                output.replace(run.range.lowerBound ..< shown.lowerBound, with: "")
                let start = output.offset
                output.keep(shown)
                delimiters[index].display = start ..< output.offset
                output.replace(shown.upperBound ..< run.range.upperBound, with: "")
            }
        }

        var strong: [Range<Int>] = []
        for pair in pairs {
            let span = delimiters[pair.opener].display.upperBound ..< delimiters[pair.closer].display.lowerBound
            guard !span.isEmpty else { continue }
            if pair.isStrong {
                strong.append(span)
                output.runs.append(PenTextRun(start: span.lowerBound, end: span.upperBound, fontWeight: PenNoteMarkdown.boldWeight))
            } else {
                output.runs.append(PenTextRun(start: span.lowerBound, end: span.upperBound, isItalic: true))
            }
        }
        for mention in mentions {
            let bold = isBold || strong.contains { $0.contains(mention.display.lowerBound) }
            output.runs.append(PenTextRun(
                start: mention.display.lowerBound, end: mention.display.upperBound,
                fontWeight: bold ? PenNoteMarkdown.boldWeight : PenNoteMarkdown.mentionWeight,
                mention: mention.name
            ))
        }
    }
}
