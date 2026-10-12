//
//  PostItCardExpansionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A prompt and a context expanded as cards (Penumbra's notes design rev 2, decision 12):
/// a prompt is a white card with its model chip, ▶ Run and the run's status; a context is
/// a quiet card with an ⓘ mark.
struct PostItCardExpansionTests {
    private let style = PenPostIt.Style.standard

    private func expansion(_ json: String, width: Double = 240, height: Double = 160) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(json), width: width, height: height, measure: PostItExpansionTests.measure
        ))
    }

    private static let queued = """
    {"id": "P1", "type": "prompt", "content": "Tighten the checkout card's copy.", "model": "claude-opus-5-5",
     "metadata": {"type": "woodcase", "woodcase": {"state": "queued", "requestedBy": "ben"}}}
    """

    // MARK: - Prompt

    @Test("A prompt is a white card, radius 8, with the hairline and the note's shadows")
    func promptPlate() throws {
        let expansion = try expansion(Self.queued)
        #expect(expansion.variant == .prompt)
        let plate = try #require(expansion.parts.first)
        guard case let .shape(shape) = plate.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(plate.role == .plate)
        #expect(shape.form == .roundedRect(cornerRadius: style.cardCornerRadius))
        #expect(shape.fill == style.promptPaper)
        #expect(shape.hairline?.color == style.hairline)
        #expect(shape.shadows == style.shadows)
        #expect(expansion.ink == style.inkOnLight)
    }

    @Test("A prompt's header names it, and its model chip sits at the right inset")
    func promptHeader() throws {
        let expansion = try expansion(Self.queued)
        #expect(expansion.text(.header)?.string == "\u{25B6}\u{FE0E} PROMPT")
        #expect(expansion.part(.header)?.frame.x == 14)
        let chip = try #require(expansion.part(.modelChip))
        let label = try #require(expansion.part(.modelLabel))
        #expect(expansion.text(.modelLabel)?.string == "claude-opus-5-5")
        #expect(abs(chip.frame.x + chip.frame.width - (240 - 14)) < 0.001)
        #expect(chip.frame.y == 14)
        #expect(label.frame.x == chip.frame.x + style.chipPaddingX)
        guard case let .shape(pill) = chip.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(pill.fill == style.chipFill)
        #expect(pill.form == .roundedRect(cornerRadius: chip.frame.height / 2))
    }

    @Test("A prompt with no model has no chip")
    func noModel() throws {
        let expansion = try expansion(#"{"id": "P1", "type": "prompt", "content": "Go"}"#)
        #expect(expansion.part(.modelChip) == nil)
        #expect(expansion.part(.modelLabel) == nil)
    }

    @Test("▶ Run is a dark button at the bottom right inset")
    func runButton() throws {
        let expansion = try expansion(Self.queued)
        let button = try #require(expansion.part(.runButton))
        #expect(abs(button.frame.x + button.frame.width - (240 - 14)) < 0.001)
        #expect(abs(button.frame.y + button.frame.height - (160 - 14)) < 0.001)
        guard case let .shape(shape) = button.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == style.runButtonFill)
        let label = try #require(expansion.text(.runLabel))
        #expect(label.string == "\u{25B6}\u{FE0E} Run")
        #expect(label.color == style.runButtonInk)
    }

    @Test("The run's status shows its state, who requested it, and a state-colored dot")
    func status() throws {
        let expansion = try expansion(Self.queued)
        #expect(expansion.text(.status)?.string == "Queued · ben")
        let dot = try #require(expansion.part(.statusDot))
        guard case let .shape(shape) = dot.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == style.statusColor(.queued))
        #expect(dot.frame.x == 14)
        let button = try #require(expansion.part(.runButton))
        let status = try #require(expansion.part(.status))
        #expect(status.frame.x + status.frame.width <= button.frame.x)
    }

    @Test("Each run state has its own label and color", arguments: PenPostIt.RunState.allCases)
    func eachState(state: PenPostIt.RunState) throws {
        let expansion = try expansion("""
        {"id": "P1", "type": "prompt", "content": "Go", "metadata": {"woodcase": {"state": "\(state.rawValue)"}}}
        """)
        #expect(expansion.text(.status)?.string == PenPostIt.Label.status(state, requestedBy: nil).english)
        guard case let .shape(shape) = expansion.part(.statusDot)?.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == style.statusColor(state))
    }

    @Test("A prompt never run shows no status")
    func neverRun() throws {
        let expansion = try expansion(#"{"id": "P1", "type": "prompt", "content": "Go", "model": "m"}"#)
        #expect(expansion.part(.status) == nil)
        #expect(expansion.part(.statusDot) == nil)
        #expect(expansion.part(.runButton) != nil)
    }

    @Test("A prompt's body sits between its header and its run row")
    func promptBody() throws {
        let node = try PostItExpansionTests.node(Self.queued)
        let expansion = try expansion(Self.queued)
        let body = try #require(expansion.part(.body))
        let header = try #require(expansion.part(.modelChip))
        let button = try #require(expansion.part(.runButton))
        #expect(body.frame.y >= header.frame.y + header.frame.height + style.sectionGap - 0.001)
        #expect(body.frame.y + body.frame.height <= button.frame.y - style.sectionGap + 0.001)
        #expect(body.frame == PenPostIt.textFrame(of: node, width: 240, height: 160))
        #expect(expansion.text(.body)?.string == "Tighten the checkout card's copy.")
    }

    // MARK: - Context

    @Test("A context is a quiet card: its own paper, a stronger hairline, no shadow, and an ⓘ mark")
    func context() throws {
        let expansion = try expansion(#"{"id": "X1", "type": "context", "content": "The price must stay visible."}"#)
        #expect(expansion.variant == .context)
        guard case let .shape(shape) = expansion.parts.first?.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == style.contextPaper)
        #expect(shape.hairline?.color == style.contextHairline)
        #expect(shape.shadows.isEmpty)
        let mark = try #require(expansion.part(.infoMark))
        #expect(mark.frame == PenRect(x: 14, y: 14, width: style.infoMarkDiameter, height: style.infoMarkDiameter))
        guard case let .shape(ring) = mark.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(ring.form == .ellipse)
        #expect(ring.fill == nil)
        #expect(ring.hairline?.width == style.infoMarkStroke)
        #expect(expansion.text(.infoGlyph)?.string == "i")
        #expect(expansion.text(.header)?.string == "CONTEXT")
        #expect(expansion.part(.runButton) == nil)
        #expect(expansion.part(.author) == nil)
    }

    @Test("Cards ignore a tint")
    func cardsIgnoreTint() throws {
        let expansion = try expansion(##"{"id": "P1", "type": "prompt", "content": "Go", "metadata": {"woodcase": {"tint": "#37474F"}}}"##)
        guard case let .shape(shape) = expansion.parts.first?.paint else { throw CocoaError(.coderInvalidValue) }
        #expect(shape.fill == style.promptPaper)
    }
}
