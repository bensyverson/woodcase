//
//  PenNoteMarkdown.swift
//  Woodcase
//

import Foundation

/// A note's or comment's markdown, parsed into the text a layout sets and the styling
/// over it.
///
/// A note keeps markdown in its `content` (Penumbra's notes design, decision 6): Pen
/// shows the source as written and keeps it intact, and Woodcase draws it styled. The
/// styling is derived from the source every time, never stored — the file keeps only
/// the markdown. Parsing gives:
///
/// - ``displayText``: the words with the syntax removed (`**bold**` → `bold`) and list
///   markers drawn as glyphs (`- ` → `•⇥`, `- [ ] ` → `☐⇥`);
/// - ``runs``: ``PenTextRun``s over the display text — headings larger and bold, bold,
///   italic, and each `@mention` carrying the name it mentions;
/// - ``indents``: a hanging indent per list item (``PenParagraphIndent``);
/// - ``checklistItems``: each `[ ]`/`[x]`, with its source range, so a click can toggle
///   it in the file;
/// - ``offsetMap``: display offsets to source offsets and back.
///
/// ```swift
/// let note = PenNoteMarkdown("# Plan\n- [ ] Ship it, @claude", fontSize: 14)
/// note.displayText                        // "Plan\n☐\tShip it, @claude"
/// note.runs.first?.fontSize               // 21: the heading, 1.5 × 14
/// note.checklistItems[0].markerSourceRange // 9 ..< 12: the "[ ]"
/// note.toggling(note.checklistItems[0])   // "# Plan\n- [x] Ship it, @claude"
/// ```
///
/// The subset, and why the rest shows as written, is in <doc:NoteMarkdown>.
public struct PenNoteMarkdown: Friendly {
    // MARK: Scale

    /// How much larger than the note's font size each heading level is set: `#` 1.5×,
    /// `##` 1.25×, `###` 1.1×.
    public static let headingScales: [Double] = [1.5, 1.25, 1.1]

    /// The CSS weight headings and `**bold**` are set in.
    public static let boldWeight: Double = 700

    /// The CSS weight an `@mention` is set in outside bold, as the rev 2 mockup draws it.
    public static let mentionWeight: Double = 600

    /// Each list level's indent, in multiples of the note's font size: the marker sits
    /// at `level × listIndent` and the item's words one `listIndent` further in.
    public static let listIndent: Double = 1.5

    /// How many leading spaces make one list nesting level (a tab is one level).
    public static let spacesPerLevel = 2

    /// The glyph a bullet list item (`-`, `*`, `+`) draws as.
    public static let bulletGlyph = "•"

    /// The glyph an open checklist item (`- [ ]`) draws as.
    public static let uncheckedGlyph = "☐"

    /// The glyph a done checklist item (`- [x]`) draws as.
    public static let checkedGlyph = "☑"

    // MARK: Parsed

    /// The markdown, as the note's `content` holds it.
    public let source: String

    /// The font size the runs and indents were sized for: the note's.
    public let fontSize: Double

    /// The text a layout sets: the source with its syntax removed and its markers drawn.
    public let displayText: String

    /// The styled runs over ``displayText``, offsets in UTF-16 code units.
    public let runs: [PenTextRun]

    /// The list items' hanging indents over ``displayText``.
    public let indents: [PenParagraphIndent]

    /// The checklist items, in order.
    public let checklistItems: [ChecklistItem]

    /// The map between ``source`` and ``displayText`` offsets.
    public let offsetMap: PenTextOffsetMap

    /// Parses a note's markdown.
    ///
    /// - Parameters:
    ///   - source: The note's `content`.
    ///   - fontSize: The note's font size, which headings and list indents scale with.
    public init(_ source: String, fontSize: Double = PenTextStyle.defaultFontSize) {
        self.source = source
        self.fontSize = fontSize
        let parsed = PenMarkdownParser(source: source, fontSize: fontSize).parse()
        displayText = parsed.displayText
        runs = parsed.runs
        indents = parsed.indents
        checklistItems = parsed.checklistItems
        offsetMap = parsed.offsetMap
    }

    /// The names the note mentions, each once, in the order they first appear.
    public var mentionedNames: [String] {
        var seen: Set<String> = []
        return runs.compactMap(\.mention).filter { seen.insert($0).inserted }
    }
}
