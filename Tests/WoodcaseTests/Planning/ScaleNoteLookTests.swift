//
//  ScaleNoteLookTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Scaling a note scales its whole look (Ben's ruling of 2026-10-20, Penumbra spec §5): a
/// proportional scale multiplies the note's stored scale factor (`note.scale`) along with
/// its box and type size, and its letter spacing when set, so a note scaled by 2 draws as
/// the same note seen at twice the size — radius, padding, author line and every mark.
@MainActor
struct ScaleNoteLookTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let json = """
    {
      "version": "2.20",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 1000, "height": 1000, "layout": "none",
          "children": [
          { "type": "note", "id": "Plain", "x": 0, "y": 0, "width": 200, "height": 200,
            "content": "Plan the **launch**\\n\\n- one\\n- two\\n- [x] done\\n- [ ] open\\n\\nask @claude",
            "metadata": { "type": "woodcase", "woodcase": { "author": "ben", "tint": "#FFCC80" } } },
          { "type": "note", "id": "Spaced", "x": 300, "y": 0, "content": "Hi",
            "metadata": { "type": "woodcase", "woodcase": { "letterSpacing": 0.5, "scale": 1.5 } } },
          { "type": "prompt", "id": "Ask", "x": 600, "y": 0, "content": "Tighten", "model": "opus",
            "metadata": { "type": "woodcase", "woodcase": { "state": "queued", "requestedBy": "ben" } } }
        ] }
      ]
    }
    """

    private static func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }

    private static func scale(_ ids: [String], by factor: Double, in document: EditableDocument) throws {
        let plan = try EditPlanner.planScale(
            nodeIDs: ids, by: factor, anchor: .topLeft, in: document, layout: ScaleFixture.layout(of: document)
        )
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    /// A node's expansion at its laid-out size, measured as the layout measures.
    private static func expansion(of id: String, in document: EditableDocument) throws -> PenPostItExpansion {
        let layout = ScaleFixture.layout(of: document)
        let node = try #require(document.node(id: id))
        let rect = try #require(layout.rects[id])
        return try #require(PenPostIt.expansion(of: node, width: rect.width, height: rect.height))
    }

    // MARK: - What the scale writes

    @Test("A scale writes a note's scale factor: absent is 1, so by 2 it is 2; a factor it holds is multiplied")
    func writesFactor() throws {
        let document = try Self.document()
        try Self.scale(["Plain", "Spaced", "Ask"], by: 2, in: document)
        #expect(try ScaleFixture.value("note.scale", of: "Plain", in: document) == 2)
        #expect(try ScaleFixture.value("note.scale", of: "Spaced", in: document) == 3)
        #expect(try ScaleFixture.value("note.scale", of: "Ask", in: document) == 2)
    }

    @Test("A note's letter spacing scales with it when set")
    func letterSpacing() throws {
        let document = try Self.document()
        try Self.scale(["Spaced"], by: 2, in: document)
        #expect(try ScaleFixture.value("note.letterSpacing", of: "Spaced", in: document) == 1)
        #expect(document.node(id: "Spaced")?.noteTextStyle?.letterSpacing == 1)
    }

    @Test("A scaled factor keeps four decimals, so the look tracks the type size")
    func factorPrecision() throws {
        let document = try Self.document()
        try Self.scale(["Plain"], by: 20.0 / 13.0, in: document)
        #expect(try ScaleFixture.value("note.scale", of: "Plain", in: document) == 1.5385)
    }

    // MARK: - What it draws

    @Test("A note scaled by 2 expands to every part of the note at twice the size", arguments: ["Plain", "Ask"])
    func everyPartDoubles(id: String) throws {
        let document = try Self.document()
        let before = try Self.expansion(of: id, in: document)
        try Self.scale([id], by: 2, in: document)
        let after = try Self.expansion(of: id, in: document)

        #expect(after.parts.map(\.role) == before.parts.map(\.role))
        for (old, new) in zip(before.parts, after.parts) {
            let doubled = { (was: Double, now: Double, measured: Bool) in
                abs(now - 2 * was) <= (measured ? 2 + 0.1 * 2 * was : 0.5)
            }
            // Every part's height is the look's, or a line of type at twice the size.
            #expect(doubled(old.frame.height, new.frame.height, false), "\(new.role) height \(old.frame) → \(new.frame)")
            // Where text decides a part's place or width, it may stray by a few percent: text
            // at 26 pt is not exactly twice text at 13 pt (line heights are whole points, and
            // the font's tracking changes with its size, and a label's width is rounded up to
            // a whole point). Everything else doubles exactly.
            let placedByText = Self.placedByText.contains(new.role)
            let sizedByText = placedByText || Self.sizedByText.contains(new.role)
            #expect(doubled(old.frame.x, new.frame.x, placedByText), "\(new.role) x \(old.frame) → \(new.frame)")
            #expect(doubled(old.frame.y, new.frame.y, placedByText), "\(new.role) y \(old.frame) → \(new.frame)")
            #expect(doubled(old.frame.width, new.frame.width, sizedByText), "\(new.role) width \(old.frame) → \(new.frame)")
            switch (old.paint, new.paint) {
            case let (.shape(was), .shape(now)):
                if case let .roundedRect(radius) = was.form, case let .roundedRect(scaled) = now.form {
                    #expect(abs(scaled - 2 * radius) <= 0.5, "\(new.role) radius")
                }
                #expect(now.hairline?.width == was.hairline.map { 2 * $0.width }, "\(new.role) hairline")
                #expect(now.shadows.map(\.blur) == was.shadows.map { 2 * $0.blur }, "\(new.role) shadows")
            case let (.text(was), .text(now)):
                #expect(now.style.fontSize == 2 * was.style.fontSize, "\(new.role) type size")
            default:
                Issue.record("\(new.role) changed paint")
            }
        }
    }

    /// The parts the body's lines place: a mark sits on its line, a pill on its words, and a
    /// right-aligned chip or button where its word's width leaves it.
    private static let placedByText: Set<PenPostItExpansion.Role> = [
        .mentionPill, .bullet, .checkbox, .checkMark, .modelChip, .modelLabel, .runButton, .runLabel,
    ]

    /// The parts as wide as a measured word.
    private static let sizedByText: Set<PenPostItExpansion.Role> = [.author, .header, .status]

    @Test("In the CG render, a note scaled by 2 at 1x has the note's look at 2x: its corners, edges, padding and author dot")
    func renderMatches() throws {
        let document = try Self.document()
        let before = try Self.render("Plain", in: document, scale: 2)
        try Self.scale(["Plain"], by: 2, in: document)
        let after = try Self.render("Plain", in: document, scale: 1)
        let dot = try #require(Self.expansion(of: "Plain", in: document).part(.identityDot)?.frame)

        #expect(before.width == after.width && before.height == after.height)
        // The padding band all round holds only the paper, its rounded corners and its
        // hairline; the type is set inside it. The author's dot is the look's too.
        let pad = 2 * Int(PenPostIt.textInsets.left) - 2
        var look: [(Int, Int)] = []
        for y in 0 ..< before.height {
            for x in 0 ..< before.width where x < pad || y < pad || x >= before.width - pad {
                look.append((x, y))
            }
        }
        for y in Int(dot.y) ..< Int(dot.y + dot.height) {
            for x in Int(dot.x) ..< Int(dot.x + dot.width) {
                look.append((x, y))
            }
        }
        let differing = look.filter { x, y in
            let old = before.pixel(x, y)
            let new = after.pixel(x, y)
            return (0 ..< 4).contains { abs(old[$0] - new[$0]) > 24 }
        }
        #expect(differing.count <= look.count / 1000, "\(differing.count) of \(look.count) pixels differ")
    }

    /// Renders one node of the document alone, at its laid-out size.
    private static func render(_ id: String, in document: EditableDocument, scale: CGFloat) throws -> PixelGrid {
        let layout = ScaleFixture.layout(of: document)
        let rect = try #require(layout.rects[id])
        let image = try #require(PenRenderer.render(
            layout.document, layoutRects: layout.rects, size: CGSize(width: rect.width, height: rect.height),
            scale: scale, rootNodeID: id
        ))
        return try #require(PixelGrid(image))
    }
}
