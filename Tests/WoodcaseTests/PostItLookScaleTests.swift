//
//  PostItLookScaleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note's look takes its size from the note's stored scale factor
/// (``PenMetadata/WoodcaseKey/scale``, `note.scale`), not from its type size (Ben's ruling of
/// 2026-10-20, Penumbra spec §5): the corner radius, the padding, the hairline, the shadows,
/// the author line and a card's chrome all multiply by it, absent being 1; changing the type
/// size alone leaves them as they are. Prompts and contexts share the look and follow.
struct PostItLookScaleTests {
    private static let style = PenPostIt.Style.standard

    /// A note, prompt or context parsed from its JSON object.
    private static func node(_ json: String) throws -> PenNode {
        try PostItExpansionTests.node(json)
    }

    private func expansion(_ json: String, width: Double = 200, height: Double = 200) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(
            of: Self.node(json), width: width, height: height, measure: PostItExpansionTests.measure
        ))
    }

    private static func note(_ woodcase: String) -> String {
        #"{"id": "N1", "type": "note", "content": "x", "metadata": {"type": "woodcase", "woodcase": {\#(woodcase)}}}"#
    }

    private static func plateShape(_ expansion: PenPostItExpansion) throws -> PenPostItExpansion.Shape {
        guard case let .shape(shape)? = expansion.part(.plate)?.paint else { throw CocoaError(.coderInvalidValue) }
        return shape
    }

    // MARK: - The note

    @Test("A note's scale multiplies its corner radius, hairline and shadows")
    func paperScales() throws {
        let shape = try Self.plateShape(expansion(Self.note(#""author": "ben", "scale": 2"#)))
        #expect(shape.form == .roundedRect(cornerRadius: 2 * Self.style.noteCornerRadius))
        #expect(shape.hairline?.width == 2 * Self.style.hairlineWidth)
        #expect(shape.shadows.map(\.offsetY) == Self.style.shadows.map { 2 * $0.offsetY })
        #expect(shape.shadows.map(\.blur) == Self.style.shadows.map { 2 * $0.blur })
    }

    @Test("A note's scale multiplies its padding and its author line")
    func paddingAndAuthorLineScale() throws {
        let node = try Self.node(Self.note(#""author": "ben", "scale": 2"#))
        let insets = try #require(PenPostIt.bodyInsets(of: node))
        let labelLine = 2 * Self.style.labelFontSize * Self.style.labelLineHeight
        #expect(insets.top == 2 * PenPostIt.textInsets.top)
        #expect(insets.left == 2 * PenPostIt.textInsets.left)
        #expect(abs(insets.bottom - (2 * PenPostIt.textInsets.bottom + 2 * Self.style.footerGap + labelLine)) < 0.001)
        let expansion = try expansion(Self.note(#""author": "ben", "scale": 2"#))
        #expect(expansion.part(.identityDot)?.frame.width == 2 * Self.style.identityDotDiameter)
        #expect(expansion.part(.identityDot)?.frame.x == 2 * PenPostIt.textInsets.left)
        #expect(expansion.text(.author)?.style.fontSize == 2 * Self.style.labelFontSize)
        #expect(expansion.part(.body)?.frame.x == 2 * PenPostIt.textInsets.left)
    }

    @Test("Changing a note's type size alone leaves its look as it is")
    func typeSizeLeavesLook() throws {
        let plain = try expansion(Self.note(#""author": "ben""#))
        let large = try expansion(Self.note(#""author": "ben", "fontSize": 26"#))
        #expect(try Self.plateShape(large) == Self.plateShape(plain))
        #expect(large.part(.identityDot) == plain.part(.identityDot))
        #expect(large.text(.author)?.style == plain.text(.author)?.style)
        #expect(large.part(.body)?.frame == plain.part(.body)?.frame)
        let node = try Self.node(Self.note(#""author": "ben", "fontSize": 26"#))
        let plainNode = try Self.node(Self.note(#""author": "ben""#))
        #expect(PenPostIt.bodyInsets(of: node) == PenPostIt.bodyInsets(of: plainNode))
    }

    @Test("A note with no scale, or one that is not a positive number, draws at 1", arguments: ["", #", "scale": 0"#, #", "scale": -2"#, #", "scale": "big""#, #", "scale": 1"#])
    func absentScaleIsOne(written: String) throws {
        let reference = try expansion(Self.note(#""author": "ben""#))
        #expect(try expansion(Self.note(#""author": "ben"\#(written)"#)) == reference)
        #expect(try Self.node(Self.note(#""author": "ben"\#(written)"#)).noteScale == 1)
    }

    @Test("A note reads its scale from its metadata")
    func noteScaleReads() throws {
        #expect(try Self.node(Self.note(#""scale": 1.5"#)).noteScale == 1.5)
        #expect(try Self.node(Self.note(#""scale": 3"#)).noteScale == 3)
        let text = try Self.node(#"{"id": "T1", "type": "text", "content": "x"}"#)
        #expect(text.noteScale == nil)
    }

    @Test("A note's paper effects, which its painted extent counts, scale with it")
    func paperEffectsScale() throws {
        let effects = try #require(PenPostIt.paperEffects(of: Self.node(Self.note(#""scale": 2"#))))
        let expected = Self.style.shadows.map {
            PenPostItExpansion.Shadow(offsetX: 2 * $0.offsetX, offsetY: 2 * $0.offsetY, blur: 2 * $0.blur, color: $0.color)
                .effect
        }
        #expect(effects == expected)
    }

    // MARK: - Cards

    @Test("A prompt's radius, padding, chip and run row scale with its scale, not its type size")
    func promptScales() throws {
        let json = { (woodcase: String) in
            #"{"id": "P1", "type": "prompt", "content": "x", "model": "opus", "metadata": {"type": "woodcase", "woodcase": {"state": "queued"\#(woodcase)}}}"#
        }
        let plain = try expansion(json(""), width: 240, height: 400)
        let scaled = try expansion(json(#", "scale": 2"#), width: 240, height: 400)
        let typed = try expansion(json(#", "fontSize": 26"#), width: 240, height: 400)
        #expect(try Self.plateShape(scaled).form == .roundedRect(cornerRadius: 2 * Self.style.cardCornerRadius))
        #expect(try #require(scaled.part(.modelChip)).frame.height == 2 * #require(plain.part(.modelChip)).frame.height)
        #expect(try #require(scaled.part(.runButton)).frame.height == 2 * #require(plain.part(.runButton)).frame.height)
        #expect(scaled.part(.statusDot)?.frame.width == 2 * Self.style.statusDotDiameter)
        #expect(scaled.part(.header)?.frame.x == 2 * PenPostIt.textInsets.left)
        #expect(typed.part(.modelChip) == plain.part(.modelChip))
        #expect(typed.part(.runButton) == plain.part(.runButton))
        #expect(typed.part(.body)?.frame == plain.part(.body)?.frame)
    }

    @Test("A context's ⓘ mark and header scale with its scale")
    func contextScales() throws {
        let json = { (woodcase: String) in
            #"{"id": "C1", "type": "context", "content": "x", "metadata": {"type": "woodcase", "woodcase": {\#(woodcase)}}}"#
        }
        let scaled = try expansion(json(#""scale": 2"#), width: 240, height: 400)
        #expect(scaled.part(.infoMark)?.frame.width == 2 * Self.style.infoMarkDiameter)
        #expect(scaled.part(.infoMark)?.frame.x == 2 * PenPostIt.textInsets.left)
        #expect(try Self.plateShape(scaled).hairline?.width == 2 * Self.style.hairlineWidth)
        let typed = try expansion(json(#""fontSize": 26"#), width: 240, height: 400)
        #expect(typed.part(.infoMark)?.frame.width == Self.style.infoMarkDiameter)
    }
}
