//
//  PenMention.swift
//  Woodcase
//

import Foundation

/// One `@mention` in a note's or comment's raw markdown: the name it mentions and where
/// it sits in the source.
///
/// The rule is the one ``PenNoteMarkdown`` parses by, not a second copy of it: an `@`
/// that follows no name character and no other `@` — so an address is not one — then
/// name characters (letters, digits, `-`, `_` and `.`), with a trailing `.` ending the
/// sentence rather than the name; never inside a code span, and never after a backslash.
/// ``mentions(in:)`` runs the parser itself and reads its mention runs back to source
/// offsets, so an editor drawing pills over raw text agrees with the note drawn styled.
///
/// ```swift
/// PenMention.mentions(in: "hi @claude and @ben.")
/// // [PenMention(name: "claude", range: 3 ..< 10), PenMention(name: "ben", range: 15 ..< 19)]
/// PenMention.query(atCaret: 6, in: "hi @cl")
/// // Query(text: "cl", range: 3 ..< 6)
/// ```
public struct PenMention: Friendly {
    /// The name mentioned, without its `@`.
    public var name: String

    /// The `@` and the name, in UTF-16 offsets into the source.
    public var range: Range<Int>

    /// Creates a mention.
    ///
    /// - Parameters:
    ///   - name: The name, without its `@`.
    ///   - range: The `@` and the name, in UTF-16 offsets into the source.
    public init(name: String, range: Range<Int>) {
        self.name = name
        self.range = range
    }

    /// The `@name` being typed at a caret: what a mention picker filters by, and what
    /// choosing a name replaces.
    public struct Query: Friendly {
        /// What has been typed after the `@`, up to the caret; empty right after the `@`.
        public var text: String

        /// The `@` and the whole name around the caret — reaching past the caret to the
        /// name's end, a trailing `.` included — in UTF-16 offsets.
        public var range: Range<Int>

        /// Creates a query.
        ///
        /// - Parameters:
        ///   - text: What has been typed after the `@`, up to the caret.
        ///   - range: The `@` and the whole name around the caret, in UTF-16 offsets.
        public init(text: String, range: Range<Int>) {
            self.text = text
            self.range = range
        }
    }

    /// Every mention in raw markdown, in order.
    ///
    /// - Parameter source: A note's or comment's markdown, as its `content` holds it.
    /// - Returns: Each mention's name and source range; a name mentioned twice appears
    ///   twice.
    public static func mentions(in source: String) -> [PenMention] {
        let note = PenNoteMarkdown(source)
        return note.runs.compactMap { run in
            guard let name = run.mention else { return nil }
            // A mention is kept as written, so its display range maps to source one for one.
            let range = note.offsetMap.sourceRange(forDisplayRange: run.start ..< run.end)
            return PenMention(name: name, range: range)
        }
    }

    /// The mention being typed at a caret, or `nil` when the caret is not in one.
    ///
    /// The caret is in a query when name characters run back from it to an `@` that
    /// would open a mention once a name follows it — so a lone `@` opens an empty query,
    /// while one in an address, in a code span or after a backslash opens none.
    ///
    /// - Parameters:
    ///   - caret: The insertion point, in UTF-16 offsets.
    ///   - source: The raw markdown.
    /// - Returns: The query, or `nil`.
    public static func query(atCaret caret: Int, in source: String) -> Query? {
        let units = Array(source.utf16)
        guard caret >= 0, caret <= units.count else { return nil }
        var start = caret
        while let previous = scalar(endingAt: start, in: units), PenMarkdownInline.isNameCharacter(previous.scalar) {
            start -= previous.width
        }
        let at = start - 1
        guard at >= 0, units[at] == PenMarkdownUnit.at, opens(at: at, in: units) else { return nil }
        var end = caret
        while let next = scalar(startingAt: end, in: units), PenMarkdownInline.isNameCharacter(next.scalar) {
            end += next.width
        }
        return Query(text: String(decoding: units[start ..< caret], as: UTF16.self), range: at ..< end)
    }

    // MARK: - Private

    /// A name character the probe in ``opens(at:in:)`` writes after an `@`.
    private static let probe: [UInt16] = Array("x".utf16)

    /// Whether the `@` at `index` opens a mention once a name follows it.
    ///
    /// Answered by the parser rather than restated: a one-letter name is written after
    /// the `@` and the markdown parsed, so a code span, an escape or a name character
    /// before the `@` decide exactly as they do in a note.
    private static func opens(at index: Int, in units: [UInt16]) -> Bool {
        var probed = units
        probed.insert(contentsOf: probe, at: index + 1)
        let text = String(decoding: probed, as: UTF16.self)
        return mentions(in: text).contains { $0.range.lowerBound == index }
    }

    /// The scalar starting at `index`, and how many UTF-16 units it takes.
    private static func scalar(startingAt index: Int, in units: [UInt16]) -> (scalar: Unicode.Scalar, width: Int)? {
        guard index >= 0, index < units.count else { return nil }
        let end = min(index + 2, units.count)
        var iterator = units[index ..< end].makeIterator()
        var decoder = UTF16()
        guard case let .scalarValue(scalar) = decoder.decode(&iterator) else { return nil }
        return (scalar, UTF16.width(scalar))
    }

    /// The scalar ending just before `index`, and how many UTF-16 units it takes.
    private static func scalar(endingAt index: Int, in units: [UInt16]) -> (scalar: Unicode.Scalar, width: Int)? {
        guard index > 0, index <= units.count else { return nil }
        if UTF16.isTrailSurrogate(units[index - 1]), index >= 2, UTF16.isLeadSurrogate(units[index - 2]) {
            return scalar(startingAt: index - 2, in: units)
        }
        return scalar(startingAt: index - 1, in: units)
    }
}
