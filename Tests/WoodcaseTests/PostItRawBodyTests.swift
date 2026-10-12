//
//  PostItRawBodyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A card being edited draws its body raw — the content as written, in its text style,
/// with no markdown runs, marks or indents — so an editor's draft lies over it, while its
/// chrome stays put (Penumbra's notes design, decision 6).
struct PostItRawBodyTests {
    /// A measurer every platform agrees on: 6 points a character, one 15-point line.
    private static let measure: TextMeasurer = { request in
        (Double(request.text.count) * 6, 15)
    }

    private static let markdown = "### Plan\\n**Bold** and *soft*, @ben\\n- item\\n- [x] done\\n- [ ] open"
    private static let written = "### Plan\n**Bold** and *soft*, @ben\n- item\n- [x] done\n- [ ] open"

    /// A note, a prompt and a context, each with every chrome part it can draw.
    private static let cards = [
        ##"{"id": "N1", "type": "note", "content": "\##(markdown)", "metadata": {"type": "woodcase", "woodcase": {"author": "ben", "tint": "#37474F"}}}"##,
        #"{"id": "P1", "type": "prompt", "model": "opus", "content": "\#(markdown)", "metadata": {"type": "woodcase", "woodcase": {"state": "running", "requestedBy": "ben"}}}"#,
        #"{"id": "X1", "type": "context", "content": "\#(markdown)"}"#,
    ]

    private static let marks: Set<PenPostItExpansion.Role> = [.mentionPill, .bullet, .checkbox, .checkMark]

    private func expansion(_ json: String, body: PenPostIt.BodyText) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(json), width: 220, height: 260, measure: Self.measure, body: body
        ))
    }

    @Test("A raw body is the content as written, in the note's text style, as one run", arguments: cards)
    func verbatim(_ json: String) throws {
        let node = try PostItExpansionTests.node(json)
        let raw = try #require(try expansion(json, body: .raw).text(.body))
        let styled = try #require(try expansion(json, body: .styled).text(.body))
        #expect(raw.string == Self.written)
        #expect(raw.runs.isEmpty)
        #expect(raw.indents.isEmpty)
        #expect(raw.style == node.noteTextStyle)
        #expect(raw.color == styled.color)
    }

    @Test("A raw body draws no marks and lists no mentions or checkboxes", arguments: cards)
    func noMarks(_ json: String) throws {
        let styled = try expansion(json, body: .styled)
        #expect(styled.parts.contains { Self.marks.contains($0.role) }, "the styled body has marks to drop")
        let raw = try expansion(json, body: .raw)
        #expect(!raw.parts.contains { Self.marks.contains($0.role) })
        #expect(raw.mentions.isEmpty)
        #expect(raw.checkboxes.isEmpty)
    }

    @Test("The chrome, the box and the body's frame are the same with and without a raw body", arguments: cards)
    func sameChrome(_ json: String) throws {
        let styled = try expansion(json, body: .styled)
        let raw = try expansion(json, body: .raw)
        let chrome = { (expansion: PenPostItExpansion) in
            expansion.parts.filter { $0.role != .body && !Self.marks.contains($0.role) }
        }
        #expect(chrome(raw) == chrome(styled))
        #expect(raw.part(.body)?.frame == styled.part(.body)?.frame)
        #expect(raw.width == styled.width)
        #expect(raw.height == styled.height)
        #expect(raw.ink == styled.ink)
        #expect(raw.identity == styled.identity)
        #expect(raw.variant == styled.variant)
    }

    @Test("A raw body of whitespace and markers is still drawn, as written")
    func markersOnly() throws {
        let raw = try expansion(#"{"id": "N1", "type": "note", "content": "- "}"#, body: .raw)
        #expect(raw.text(.body)?.string == "- ")
    }

    @Test("Drawing options draw a listed card's body raw and every other card's styled")
    func options() throws {
        let options = PenPostIt.DrawingOptions(rawBodies: ["N1"])
        #expect(options.bodyText(for: "N1") == .raw)
        #expect(options.bodyText(for: "N2") == .styled)
        let listed = try PostItExpansionTests.node(Self.cards[0])
        let raw = try #require(PenPostIt.expansion(
            of: listed, width: 220, height: 260, measure: Self.measure, options: options
        ))
        #expect(raw.text(.body)?.string == Self.written)
        let other = try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(Self.cards[1]), width: 220, height: 260, measure: Self.measure,
            options: options
        ))
        #expect(other.text(.body)?.string != Self.written)
    }

    @Test("The options overload passes the caller's labels and identity colors through")
    func optionsPassThrough() throws {
        let chosen = PenHexColor(red: 0x12, green: 0x34, blue: 0xEF)
        let options = PenPostIt.DrawingOptions(
            labels: { $0 == .run ? "Go" : $0.english }, identityColor: { $0 == "ben" ? chosen : nil }
        )
        let prompt = try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(Self.cards[1]), width: 220, height: 260, measure: Self.measure,
            options: options
        ))
        #expect(prompt.text(.runLabel)?.string.hasSuffix("Go") == true)
        let note = try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(Self.cards[0]), width: 220, height: 260, measure: Self.measure,
            options: options
        ))
        #expect(note.identity?.color == chosen)
    }
}
