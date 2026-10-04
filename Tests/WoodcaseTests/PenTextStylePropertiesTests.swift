//
//  PenTextStylePropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A note, prompt or context resolves its TextStyle keys through ``PenTextStyle`` with the
/// same defaults a text node gets, because all four carry the format's one key set.
struct PenTextStylePropertiesTests {
    @Test("A note's PenTextStyle equals a text node's with the same keys")
    func noteMatchesText() {
        let text = PenNode.TextData(
            fontFamily: .literal("Inter"), fontSize: .literal(20), fontWeight: .literal("700"),
            fontStyle: .literal("italic"), letterSpacing: .literal(1), lineHeight: .literal(1.3),
            textAlign: .center, textAlignVertical: .middle, underline: .literal(true)
        )
        let note = PenNode.NoteData(
            fontFamily: .literal("Inter"), fontSize: .literal(20), fontWeight: .literal("700"),
            fontStyle: .literal("italic"), letterSpacing: .literal(1), lineHeight: .literal(1.3),
            textAlign: .center, textAlignVertical: .middle, underline: .literal(true)
        )

        #expect(PenTextStyle(note) == PenTextStyle(text))
        #expect(PenTextStyle(note).fontSize == 20)
    }

    @Test("An unstyled prompt and context take the same defaults as an unstyled text")
    func defaultsMatch() {
        let text = PenTextStyle(PenNode.TextData())
        #expect(PenTextStyle(PenNode.PromptData()) == text)
        #expect(PenTextStyle(PenNode.ContextData()) == text)
    }
}
