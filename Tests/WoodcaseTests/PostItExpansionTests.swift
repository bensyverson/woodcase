//
//  PostItExpansionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note expanded into the parts every renderer draws (Penumbra's notes design rev 2,
/// decisions 12–13): the paper, its body text from the markdown, and the author's
/// identity dot and name at the bottom — no kind mark. Comments are Penumbra's to draw.
struct PostItExpansionTests {
    /// A measurer every platform agrees on: 6 points a character, one 15-point line.
    static let measure: TextMeasurer = { request in
        (Double(request.text.count) * 6, 15)
    }

    /// A note parsed from its JSON object.
    static func node(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(#"{"version": "2.20", "children": ["# + json + "]}")
        return try #require(document.children.first)
    }

    private func expansion(_ json: String, width: Double = 200, height: Double = 200) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(of: Self.node(json), width: width, height: height, measure: Self.measure))
    }

    private static let authored = """
    {"id": "N1", "type": "note", "content": "@claude should the dot show?",
     "metadata": {"type": "woodcase", "woodcase": {"author": "ben"}}}
    """

    // MARK: - The paper

    @Test("The plate fills the note in Post-it yellow, radius 6, with a 6% black hairline and two soft shadows")
    func plate() throws {
        let style = PenPostIt.Style.standard
        let parts = try expansion(Self.authored).parts
        let plate = try #require(parts.first)
        #expect(plate.role == .plate)
        #expect(plate.frame == PenRect(x: 0, y: 0, width: 200, height: 200))
        guard case let .shape(shape) = plate.paint else {
            Issue.record("the plate is \(plate.paint)")
            return
        }
        #expect(shape.form == .roundedRect(cornerRadius: 6))
        #expect(shape.fill == PenPostIt.Tint.yellow.color)
        #expect(try shape.hairline == PenPostItExpansion.Hairline(color: #require(PenHexColor("#0000000F")), width: 1))
        #expect(shape.shadows == style.shadows)
        #expect(shape.shadows.count == 2)
    }

    @Test("A note's tint paints the plate, and a dark tint turns the ink white")
    func tintAndInk() throws {
        let expansion = try expansion("""
        {"id": "N1", "type": "note", "content": "Ask", "metadata": {"type": "woodcase", "woodcase": {"tint": "#37474F", "author": "ben"}}}
        """)
        guard case let .shape(shape) = expansion.parts.first?.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == PenHexColor("#37474F"))
        #expect(expansion.ink == PenPostIt.Style.standard.inkOnDark)
        #expect(expansion.text(.body)?.color == PenPostIt.Style.standard.inkOnDark.primary)
        #expect(expansion.text(.author)?.color == PenPostIt.Style.standard.inkOnDark.secondary)
    }

    @Test("A malformed tint draws Post-it yellow")
    func malformedTint() throws {
        let expansion = try expansion(#"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"tint": "teal"}}}"#)
        guard case let .shape(shape) = expansion.parts.first?.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == PenPostIt.Tint.yellow.color)
    }

    // MARK: - The body

    @Test("The body is the markdown's display text and runs, with its mentions' ink, set in the box above the author line")
    func body() throws {
        let node = try Self.node(Self.authored)
        let expansion = try expansion(Self.authored)
        let body = try #require(expansion.part(.body))
        guard case let .text(text) = body.paint else { throw CocoaError(.coderInvalidValue) }
        let markdown = try #require(node.noteMarkdown)
        #expect(text.string == markdown.displayText)
        // The markdown's runs, then fill-only runs that letter each mention in its pill's ink.
        #expect(Array(text.runs.prefix(markdown.runs.count)) == markdown.runs)
        #expect(text.runs.dropFirst(markdown.runs.count).allSatisfy { $0.fill != nil && $0.fontWeight == nil })
        #expect(text.style == node.noteTextStyle)
        #expect(body.frame == PenPostIt.textFrame(of: node, width: 200, height: 200))
        #expect(body.frame.x == 14 && body.frame.y == 14 && body.frame.width == 172)
        let author = try #require(expansion.part(.author))
        #expect(body.frame.y + body.frame.height <= author.frame.y, "the body runs into the author line")
    }

    @Test("A note's default text is 13 points at a line height of 1.35, as the mockup sets it")
    func defaultTextStyle() throws {
        let style = try #require(Self.node(Self.authored).noteTextStyle)
        #expect(style.fontSize == 13)
        #expect(style.lineHeight == 1.35)
    }

    @Test("Without an author there is no footer, and the body reaches the bottom inset")
    func noAuthor() throws {
        let expansion = try expansion(#"{"id": "N1", "type": "note", "content": "hi"}"#)
        #expect(expansion.part(.author) == nil)
        #expect(expansion.part(.identityDot) == nil)
        #expect(expansion.identity == nil)
        #expect(expansion.part(.body)?.frame == PenRect(x: 14, y: 14, width: 172, height: 172))
    }

    @Test("A mention is listed with its display range, name and identity color")
    func mentions() throws {
        let expansion = try expansion(Self.authored)
        #expect(expansion.mentions == [
            PenPostItExpansion.Mention(range: 0 ..< 7, name: "claude", color: ActorColor(name: "claude").color),
        ])
    }

    @Test("A ticked checklist item's words are dimmed to the tertiary ink; an open one's are not")
    func tickedItemsDim() throws {
        let node = try Self.node(#"{"id": "N1", "type": "note", "content": "- [x] Inspector dot\n- [ ] Reset menu"}"#)
        let expansion = try #require(PenPostIt.expansion(of: node, width: 200, height: 200, measure: Self.measure))
        let markdown = try #require(node.noteMarkdown)
        let ticked = try #require(markdown.checklistItems.first { $0.isChecked })
        let open = try #require(markdown.checklistItems.first { !$0.isChecked })
        let dim = PenPostIt.Style.standard.inkOnLight.tertiary
        let dimmed = try #require(expansion.text(.body)?.runs.filter { $0.fill == dim })
        #expect(dimmed.contains { $0.start == ticked.boxDisplayRange.upperBound && $0.end == ticked.lineDisplayRange.upperBound })
        #expect(!dimmed.contains { $0.range.overlaps(open.lineDisplayRange) })
    }

    // MARK: - The author

    @Test("The author's identity dot and name sit bottom-left at the inset")
    func authorFooter() throws {
        let style = PenPostIt.Style.standard
        let expansion = try expansion(Self.authored)
        let dot = try #require(expansion.part(.identityDot))
        let author = try #require(expansion.part(.author))
        #expect(dot.frame.x == 14)
        #expect(dot.frame.width == style.identityDotDiameter && dot.frame.height == style.identityDotDiameter)
        #expect(author.frame.x == 14 + style.identityDotDiameter + style.identityDotGap)
        #expect(abs(author.frame.y + author.frame.height - (200 - 14)) < 0.001)
        #expect(abs((dot.frame.y + dot.frame.height / 2) - (author.frame.y + author.frame.height / 2)) < 0.001)
        guard case let .text(name) = author.paint, case let .shape(disc) = dot.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(name.string == "ben")
        #expect(name.style.fontSize == style.labelFontSize)
        #expect(disc.form == .ellipse)
        #expect(disc.fill == ActorColor(name: "ben").color)
        #expect(expansion.identity == PenPostItExpansion.Identity(author: "ben", color: ActorColor(name: "ben").color))
    }

    @Test("An author name too wide for the footer is cut with an ellipsis")
    func longAuthorIsCut() throws {
        let long = String(repeating: "w", count: 60)
        let expansion = try expansion(
            #"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "\#(long)"}}}"#
        )
        let author = try #require(expansion.part(.author))
        #expect(author.frame.x + author.frame.width <= 200 - 14)
        #expect(expansion.text(.author)?.string.hasSuffix("…") == true)
        #expect(expansion.identity?.author == long)
    }

    // MARK: - No state

    @Test(
        "A note with state resolved draws exactly like the same note without it",
        arguments: ["resolved", "open", "closed"]
    )
    func stateIsNotDrawn(state: String) throws {
        let with = try expansion("""
        {"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "ben", "state": "\(state)"}}}
        """)
        let without = try expansion("""
        {"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "ben"}}}
        """)
        #expect(with == without)
        let legacy = try expansion("""
        {"id": "N1", "type": "note", "content": "x", "metadata": {"type": "postit", "author": "ben", "state": "\(state)"}}
        """)
        #expect(legacy == without)
    }

    @Test("A note with only a state and no author has no footer")
    func stateAloneHasNoFooter() throws {
        let node = try Self.node(#"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"state": "resolved"}}}"#)
        #expect(PenPostIt.bodyInsets(of: node) == PenPostIt.textInsets)
    }

    // MARK: - What is not drawn here

    @Test("A comment is not expanded: Penumbra draws comments")
    func commentIsNotExpanded() throws {
        let node = try Self.node(#"{"id": "C1", "type": "note", "content": "hi", "metadata": {"woodcase": {"type": "comment"}}}"#)
        #expect(PenPostIt.expansion(of: node, width: 200, height: 200, measure: Self.measure) == nil)
    }

    @Test("A node that is not a note, prompt or context is not expanded")
    func otherNodes() throws {
        let node = try Self.node(#"{"id": "T1", "type": "text", "content": "hi"}"#)
        #expect(PenPostIt.expansion(of: node, width: 200, height: 200, measure: Self.measure) == nil)
    }

    @Test("A note has no kind mark: its parts are the plate, the body and the footer")
    func noKindMark() throws {
        let legacy = try expansion("""
        {"id": "N1", "type": "note", "content": "x", "metadata": {"type": "postit", "kind": "question", "author": "claude"}}
        """)
        #expect(Set(legacy.parts.map(\.role)) == [.plate, .body, .identityDot, .author])
    }

    @Test("An empty note draws its plate and footer and no body")
    func emptyNote() throws {
        let expansion = try expansion(#"{"id": "N1", "type": "note", "content": "", "metadata": {"woodcase": {"author": "ben"}}}"#)
        #expect(expansion.part(.body) == nil)
        #expect(expansion.part(.author) != nil)
    }

    @Test("Every shape part converts to a node with its frame's size")
    func shapeNodes() throws {
        let expansion = try expansion(Self.authored)
        let plate = try #require(expansion.parts.first)
        guard case let .shape(shape) = plate.paint else { throw CocoaError(.coderInvalidValue) }
        let node = shape.node(id: "N1/plate", frame: plate.frame)
        guard case let .rectangle(data) = node.kind else {
            Issue.record("the plate converts to \(node.kind)")
            return
        }
        #expect(data.width == .fixed(200))
        #expect(data.cornerRadius == .uniform(.literal(6)))
        #expect(data.strokeAlignment == .inner)
    }
}
