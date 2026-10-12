//
//  PostItMarksTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The marks a note's body draws as shapes rather than glyphs (Ben's rulings on the rev 2
/// look, 2026-10-11): checklist boxes with a hit rect, list bullets at body ink, mention
/// pills in the person's identity color, and the light ring an identity dot takes on dark
/// paper.
struct PostItMarksTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private func expansion(
        _ json: String, width: Double = 200, height: Double = 200,
        identityColor: @escaping (String) -> PenHexColor? = { _ in nil }
    ) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(json), width: width, height: height,
            measure: PostItExpansionTests.measure, identityColor: identityColor
        ))
    }

    private func shape(_ part: PenPostItExpansion.Part) throws -> PenPostItExpansion.Shape {
        guard case let .shape(shape) = part.paint else { throw CocoaError(.coderInvalidValue) }
        return shape
    }

    private static let checklist = #"{"id": "N1", "type": "note", "content": "- [x] Inspector dot\n- [ ] Reset menu"}"#

    // MARK: - Checkboxes

    @Test("A checklist item draws a shape part with a hit rect, and no ☐/☑ glyph")
    func checkboxIsAShape() throws {
        let expansion = try expansion(Self.checklist)
        let body = try #require(expansion.text(.body))
        #expect(!body.string.contains("☐") && !body.string.contains("☑"))
        let boxes = expansion.parts.filter { $0.role == .checkbox }
        #expect(boxes.count == 2)
        #expect(expansion.checkboxes.count == 2)
        let markdown = try #require(PostItExpansionTests.node(Self.checklist).noteMarkdown)
        #expect(expansion.checkboxes.map(\.item) == markdown.checklistItems)
        #expect(expansion.checkboxes.map(\.frame) == boxes.map(\.frame))
        for box in boxes {
            #expect(try shape(box).form == .roundedRect(cornerRadius: PenPostIt.Style.standard.checkboxCornerRadius))
        }
    }

    @Test("A checkbox is as tall and wide as the body's cap height, on its line, at the item's indent")
    func checkboxGeometry() throws {
        let expansion = try expansion(Self.checklist)
        let body = try #require(expansion.part(.body))
        let first = try #require(expansion.checkboxes.first?.frame)
        let second = try #require(expansion.checkboxes.last?.frame)
        #expect(first.width == first.height)
        // Inter's cap height is 0.727 em: 9.45 at 13 points.
        #expect(abs(first.height - 13 * 0.727) < 0.3, "\(first.height)")
        #expect(abs(first.x - body.frame.x) < 0.5)
        #expect(first.y > body.frame.y && first.y + first.height < body.frame.y + 13 * 1.35)
        // One line apart: the 1.35 line height's pitch, which Pen rounds to a whole point.
        #expect(abs(second.y - first.y - (13 * 1.35).rounded()) < 0.01, "\(second.y - first.y)")
    }

    @Test("A done item's box is filled and carries a check mark; an open one is only edged")
    func doneBoxHasACheck() throws {
        let expansion = try expansion(Self.checklist)
        let boxes = expansion.parts.filter { $0.role == .checkbox }
        let done = try shape(boxes[0])
        let open = try shape(boxes[1])
        #expect(done.fill != nil)
        #expect(open.fill == nil)
        #expect(open.hairline != nil)
        let marks = expansion.parts.filter { $0.role == .checkMark }
        #expect(marks.count == 1)
        let mark = try #require(marks.first)
        #expect(try shape(mark).form == .checkMark)
        #expect(mark.frame == boxes[0].frame)
    }

    @Test("A check mark converts to a stroked path node with its frame's size")
    func checkMarkNode() throws {
        let expansion = try expansion(Self.checklist)
        let mark = try #require(expansion.part(.checkMark))
        let node = try shape(mark).node(id: "N1/check", frame: mark.frame)
        guard case let .path(data) = node.kind else {
            Issue.record("the check mark converts to \(node.kind)")
            return
        }
        #expect(data.width == .fixed(mark.frame.width))
        #expect(data.stroke != nil)
        #expect(data.fills == nil)
        #expect(data.strokeLinecap == .round)
    }

    // MARK: - Bullets

    @Test("Bullets draw at body ink, as dots, and no bullet glyph is set")
    func bulletsAtBodyInk() throws {
        let expansion = try expansion(#"{"id": "N1", "type": "note", "content": "- one\n- two"}"#)
        #expect(expansion.text(.body)?.string.contains("•") == false)
        let bullets = expansion.parts.filter { $0.role == .bullet }
        #expect(bullets.count == 2)
        let dot = try shape(#require(bullets.first))
        #expect(dot.form == .ellipse)
        #expect(dot.fill == expansion.ink.primary)
        let diameter = try #require(bullets.first?.frame.width)
        #expect(diameter == PenPostIt.Style.standard.bulletDiameter)
    }

    // MARK: - Mentions

    @Test("A mention draws as a pill in the person's ActorColor, lettered in its ink")
    func mentionPill() throws {
        let expansion = try expansion("""
        {"id": "N1", "type": "note", "content": "@claude should the dot show?"}
        """)
        let color = ActorColor(name: "claude")
        let pill = try #require(expansion.part(.mentionPill))
        let pillShape = try shape(pill)
        #expect(pillShape.fill == color.color)
        #expect(pillShape.form == .roundedRect(cornerRadius: pill.frame.height / 2))
        let body = try #require(expansion.part(.body))
        #expect(pill.frame.x == body.frame.x, "at a line start the pill's left edge is on the text column")
        #expect(pill.frame.y > body.frame.y && pill.frame.y + pill.frame.height < body.frame.y + 13 * 1.35)
        let paint = try #require(expansion.text(.body))
        #expect(paint.runs.contains { $0.start == 0 && $0.end == 7 && $0.fill == color.ink.color })
        #expect(expansion.mentions == [PenPostItExpansion.Mention(range: 0 ..< 7, name: "claude", color: color.color)])
        let pillIndex = try #require(expansion.parts.firstIndex { $0.role == .mentionPill })
        let bodyIndex = try #require(expansion.parts.firstIndex { $0.role == .body })
        #expect(pillIndex < bodyIndex, "the pill is drawn behind its text")
    }

    @Test("A pill's padding is laid out: the drawn body and the editor's layout break identically, around padded mentions")
    func pillPaddingIsLaidOut() throws {
        let node = try PostItExpansionTests.node("""
        {"id": "N1", "type": "note", "content": "Ask @claude and @ben whether the pills reflow a long line of text."}
        """)
        let expansion = try #require(PenPostIt.expansion(of: node, width: 200, height: 200))
        let body = try #require(expansion.part(.body))
        guard case let .text(text) = body.paint else { throw CocoaError(.coderInvalidValue) }
        let padding = PenNoteMarkdown.mentionPadding * 13
        #expect(text.runs.filter { $0.mention != nil }.allSatisfy { $0.inlinePadding == padding })
        let drawn = PenTextLayout(
            text: text.string, style: text.style, runs: text.runs, indents: text.indents,
            box: CGSize(width: body.frame.width, height: body.frame.height)
        )
        let editor = try #require(PenTextLayout(note: node, size: CGSize(width: 200, height: 200)))
        #expect(drawn.geometry.lines.map(\.stringRange) == editor.geometry.lines.map(\.stringRange))
        #expect(drawn.geometry.lines.map(\.carets) == editor.geometry.lines.map(\.carets))
        let pills = expansion.parts.filter { $0.role == .mentionPill }
        #expect(pills.count == 2)
        // "Ask @claude": the space before the mention keeps its own width, and the pill starts after it.
        let line = try #require(editor.geometry.lines.first)
        let beforeSpace = try #require(line.carets.first { $0.index == 3 }).x
        let afterSpace = try #require(line.carets.first { $0.index == 4 }).x
        #expect(afterSpace - beforeSpace > padding + 2, "the space before the mention is \(afterSpace - beforeSpace)")
        #expect(pills[0].frame.x <= body.frame.x + afterSpace, "the pill starts at or before the caret before the mention")
        #expect(pills[0].frame.x > body.frame.x + beforeSpace + 2, "the pill does not cover the space before it")
    }

    // MARK: - Caller-supplied colors

    @Test("A caller-supplied color for an identity replaces the hash in the dot and the pill")
    func suppliedColor() throws {
        let chosen = try #require(PenHexColor("#FF00AA"))
        let expansion = try expansion("""
        {"id": "N1", "type": "note", "content": "@ben and @claude", "metadata": {"woodcase": {"author": "ben"}}}
        """, identityColor: { $0 == "ben" ? chosen : nil })
        let dot = try #require(expansion.part(.identityDot))
        #expect(try shape(dot).fill == chosen)
        #expect(expansion.identity?.color == chosen)
        let pills = expansion.parts.filter { $0.role == .mentionPill }
        #expect(try pills.map { try shape($0).fill } == [chosen, ActorColor(name: "claude").color])
        let ink = ActorColor.Ink(on: chosen).color
        #expect(expansion.text(.body)?.runs.contains { $0.start == 0 && $0.end == 4 && $0.fill == ink } == true)
    }

    // MARK: - The identity dot

    @Test("An identity dot on dark paper has a light ring; on light paper it has none")
    func dotRing() throws {
        let style = PenPostIt.Style.standard
        let dark = try expansion(##"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "ben", "tint": "#37474F"}}}"##)
        let darkDot = try #require(dark.part(.identityDot))
        let ring = try #require(try shape(darkDot).hairline)
        #expect(ring == PenPostItExpansion.Hairline(color: style.identityRingOnDark, width: style.identityRingWidth))
        #expect(ring.color.relativeLuminance > 0.5)
        let light = try expansion(#"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "ben"}}}"#)
        let lightDot = try #require(light.part(.identityDot))
        #expect(try shape(lightDot).hairline == nil)
    }

    @Test("The dot is the author's ActorColor when no color is supplied")
    func dotIsActorColor() throws {
        let expansion = try expansion(#"{"id": "N1", "type": "note", "content": "x", "metadata": {"woodcase": {"author": "ben"}}}"#)
        let dot = try #require(expansion.part(.identityDot))
        #expect(try shape(dot).fill == ActorColor(name: "ben").color)
        #expect(expansion.identity == PenPostItExpansion.Identity(author: "ben", color: ActorColor(name: "ben").color))
    }
}
