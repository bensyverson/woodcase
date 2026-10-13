//
//  PenMentionTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

/// The public raw-text `@mention` scanner: each mention's source range and name, by the
/// rule note and comment markdown already uses, and the query a caret sits in.
struct PenMentionTests {
    // MARK: - Mentions

    @Test("Each mention's range covers its at sign and name, in UTF-16 source offsets")
    func rangesAndNames() {
        let mentions = PenMention.mentions(in: "hi @claude and @ben.")
        #expect(mentions == [
            PenMention(name: "claude", range: 3 ..< 10),
            PenMention(name: "ben", range: 15 ..< 19),
        ])
    }

    @Test("Ranges are source offsets across headings, list items and checkboxes")
    func rangesAcrossLines() {
        let source = "# Plan @a\n- [ ] ship, @codex-2_a.b"
        #expect(PenMention.mentions(in: source) == [
            PenMention(name: "a", range: 7 ..< 9),
            PenMention(name: "codex-2_a.b", range: 22 ..< 34),
        ])
    }

    @Test("Offsets count UTF-16 units, so a surrogate pair before a mention counts two")
    func surrogatePairs() {
        #expect(PenMention.mentions(in: "😀 @josé") == [PenMention(name: "josé", range: 3 ..< 8)])
    }

    @Test("An address, a doubled at sign, an escaped one and one in code are not mentions")
    func notMentions() {
        // Each pair: a source that holds no mention, and the nearest one that does.
        let pairs = [
            ("ben@example.com", "hi @ben"), ("@@ben", "@ben"), ("\\@ben", "\\ @ben"),
            ("`@ben`", "`x` @ben"), ("@", "@ben"), ("@ ben", "@ben"),
        ]
        for (none, one) in pairs {
            #expect(PenMention.mentions(in: none).isEmpty, "\(none)")
            #expect(PenMention.mentions(in: one).map(\.name) == ["ben"], "\(one)")
        }
    }

    @Test("The scanner finds exactly the names note markdown mentions, in order")
    func agreesWithNoteMarkdown() {
        let source = "**@bold** and *@it* `@code` a@b.c (@paren) @x.\n- @list"
        let names = PenMention.mentions(in: source).map(\.name)
        #expect(names == ["bold", "it", "paren", "x", "list"])
        #expect(PenNoteMarkdown(source).mentionedNames == names)
    }

    // MARK: - Query at the caret

    @Test("The query at a caret ending a name is what follows the at sign")
    func queryAtEndOfName() {
        #expect(PenMention.query(atCaret: 6, in: "hi @cl") == PenMention.Query(text: "cl", range: 3 ..< 6))
    }

    @Test("A caret inside a name queries up to the caret and replaces the whole name")
    func queryInsideName() {
        #expect(PenMention.query(atCaret: 5, in: "hi @claude") == PenMention.Query(text: "c", range: 3 ..< 10))
    }

    @Test("A lone at sign opens an empty query")
    func emptyQuery() {
        #expect(PenMention.query(atCaret: 1, in: "@") == PenMention.Query(text: "", range: 0 ..< 1))
        #expect(PenMention.query(atCaret: 4, in: "hi @") == PenMention.Query(text: "", range: 3 ..< 4))
    }

    @Test("A trailing period stays in the query while it is being typed")
    func trailingPeriod() {
        #expect(PenMention.query(atCaret: 3, in: "@a.") == PenMention.Query(text: "a.", range: 0 ..< 3))
    }

    @Test("No query where no mention could open: an address, code, an escape, past a space")
    func noQuery() {
        // Each: a caret in no query, then the nearest caret and source that are in one.
        let cases: [(Int, String, Int, String)] = [
            (3, "a@b", 4, "a @b"), (3, "`@a`", 4, "`` @a"), (3, "\\@a", 4, "\\ @a"),
            (4, "@a b", 2, "@a b"), (2, "hi there", 2, "@hi there"), (9, "@a", 2, "@a"), (-1, "@a", 1, "@a"),
        ]
        for (caret, source, inCaret, inSource) in cases {
            #expect(PenMention.query(atCaret: caret, in: source) == nil, "\(caret) in \(source)")
            #expect(PenMention.query(atCaret: inCaret, in: inSource) != nil, "\(inCaret) in \(inSource)")
        }
    }
}
