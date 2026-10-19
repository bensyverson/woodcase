//
//  ScalePropertyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a proportional scale multiplies (``ScaleCapture``): every length on the session 21
/// list, by one factor, descending into children — and what it leaves alone: text sizing
/// modes, line-height multiples, path geometry and bound values (Penumbra spec §5, Ben's
/// rulings of 2026-10-14 and 2026-10-18).
@MainActor
struct ScalePropertyTests {
    @Test("A frame's size, gap, padding, corner radii and per-side stroke widths scale")
    func frameLengths() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card"], by: 2, in: document)

        #expect(try ScaleFixture.value("kind.width", of: "Card", in: document) == 400)
        #expect(try ScaleFixture.value("kind.height", of: "Card", in: document) == 240)
        #expect(try ScaleFixture.value("kind.gap", of: "Card", in: document) == 16)
        #expect(try ScaleFixture.value("kind.padding", of: "Card", in: document) == [20, 24])
        #expect(try ScaleFixture.value("kind.cornerRadius", of: "Card", in: document) == [8, 12, 16, 20])
        #expect(
            try ScaleFixture.value("kind.strokeWidth", of: "Card", in: document)
                == ["top": 2, "right": 4, "bottom": 6, "left": 8]
        )
    }

    @Test("A shadow's offset and blur, a layer blur and a background blur scale, and the spread stays fresh")
    func effects() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card"], by: 2, in: document)

        let node = try #require(document.node(id: "Card"))
        let effects = PenRenderer.effects(for: node)?.all ?? []
        #expect(effects.count == 3)
        guard effects.count == 3, case let .shadow(shadow) = effects[0], case let .blur(blur) = effects[1],
              case let .backgroundBlur(background) = effects[2]
        else {
            Issue.record("effects changed shape: \(effects)")
            return
        }
        #expect(shadow.offset?.x == .literal(4))
        #expect(shadow.offset?.y == .literal(8))
        #expect(shadow.blur == .literal(12))
        #expect(shadow.color == .literal("#00000040"))
        #expect(blur.radius == .literal(6))
        #expect(background.radius == .literal(10))
        #expect(node.shadowSpread(forEffect: 0) == 4)
        #expect(!node.hasStaleShadowSpread)
    }

    @Test("A text's size, letter spacing and runs scale; its line-height multiple does not")
    func typography() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card"], by: 2, in: document)

        #expect(try ScaleFixture.value("kind.fontSize", of: "Title", in: document) == 40)
        #expect(try ScaleFixture.value("kind.letterSpacing", of: "Title", in: document) == 3)
        #expect(try ScaleFixture.value("kind.lineHeight", of: "Title", in: document) == 1.2)
        let spans = try #require(document.node(id: "Title")?.common.metadata?.textSpans)
        #expect(spans.runs.first?.fontSize == 60)
        #expect(spans.text == "Hello")
        // A text with no size of its own is drawn at 16, so it is written at 32.
        #expect(try ScaleFixture.value("kind.fontSize", of: "Boxed", in: document) == 32)
    }

    @Test("Text sizing modes are left alone: auto keeps fitting its words, fixed dimensions scale")
    func textSizingModes() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card"], by: 2, in: document)

        #expect(try ScaleFixture.value("kind.textGrowth", of: "Title", in: document) == "auto")
        #expect(try ScaleFixture.value("kind.width", of: "Title", in: document) == .null)
        #expect(try ScaleFixture.value("kind.height", of: "Title", in: document) == .null)
        #expect(try ScaleFixture.value("kind.textGrowth", of: "Body", in: document) == "fixed-width")
        #expect(try ScaleFixture.value("kind.width", of: "Body", in: document) == 300)
        #expect(try ScaleFixture.value("kind.height", of: "Body", in: document) == .null)
        #expect(try ScaleFixture.value("kind.textGrowth", of: "Boxed", in: document) == "fixed-width-height")
        #expect(try ScaleFixture.value("kind.width", of: "Boxed", in: document) == 160)
        #expect(try ScaleFixture.value("kind.height", of: "Boxed", in: document) == 80)
    }

    @Test("A uniform stroke, a radius and the dash pattern and its offset scale together")
    func strokeAndDash() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Dashed"], by: 1.5, in: document)

        #expect(try ScaleFixture.value("kind.strokeWidth", of: "Dashed", in: document) == 3)
        #expect(try ScaleFixture.value("kind.cornerRadius", of: "Dashed", in: document) == 7.5)
        let dash = try #require(document.node(id: "Dashed")?.strokeDash)
        #expect(dash.lengths == [6, 3])
        #expect(dash.phase == 1.5)
    }

    @Test("A path's box scales and its geometry, drawn into the box, is left as written")
    func pathGeometry() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Wave"], by: 3, in: document)

        #expect(try ScaleFixture.value("kind.width", of: "Wave", in: document) == 30)
        #expect(try ScaleFixture.value("kind.height", of: "Wave", in: document) == 30)
        #expect(try ScaleFixture.value("kind.geometry", of: "Wave", in: document) == "M0 0 L10 10")
    }

    @Test("A note scales as a whole: its box, from the 200 × 200 it draws at, and its type size")
    func note() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Sticky"], by: 2, in: document)

        let note = try #require(document.node(id: "Sticky"))
        #expect(note.noteTextStyle?.fontSize == 28)
        #expect(try ScaleFixture.value("kind.width", of: "Sticky", in: document) == 400)
        #expect(try ScaleFixture.value("kind.height", of: "Sticky", in: document) == 400)
    }

    @Test("Bound values stay bound and are reported as unscaled; the rest of the node still scales")
    func boundValues() throws {
        let document = try ScaleFixture.document()
        let plan = try ScaleFixture.scale(["Bound"], by: 2, in: document)

        #expect(try ScaleFixture.value("kind.gap", of: "Bound", in: document) == "$pad")
        #expect(try ScaleFixture.value("kind.padding", of: "Bound", in: document) == "$pad")
        #expect(try ScaleFixture.value("kind.width", of: "Bound", in: document) == 200)
        #expect(Set(plan.unscaled) == [
            ScalePlan.BoundValue(nodeID: "Bound", property: "kind.gap", variable: "pad"),
            ScalePlan.BoundValue(nodeID: "Bound", property: "kind.padding", variable: "pad"),
        ])
    }

    @Test("A factor below 1 shrinks, keeping fractions to a hundredth of a point")
    func shrink() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card"], by: 1.0 / 3.0, in: document)

        #expect(try ScaleFixture.value("kind.width", of: "Card", in: document) == 66.67)
        #expect(try ScaleFixture.value("kind.gap", of: "Card", in: document) == 2.67)
        #expect(try ScaleFixture.value("kind.fontSize", of: "Title", in: document) == 6.67)
        #expect(try ScaleFixture.value("kind.padding", of: "Card", in: document) == [3.33, 4])
    }

    @Test("A factor of 1 writes nothing")
    func identity() throws {
        let document = try ScaleFixture.document()
        let plan = try ScaleFixture.plan(["Card", "Turned", "Chip", "Sticky"], by: 1, in: document)

        #expect(plan.operations.isEmpty)
    }

    @Test("A factor that is not a positive number is refused")
    func invalidFactor() throws {
        let document = try ScaleFixture.document()
        for factor in [0, -2, .nan, .infinity] {
            #expect(throws: EditRefusal.self) { try ScaleFixture.plan(["Card"], by: factor, in: document) }
            do {
                _ = try ScaleFixture.plan(["Card"], by: factor, in: document)
            } catch let refusal as EditRefusal {
                #expect(refusal.code == .outOfRange)
            }
        }
    }
}
