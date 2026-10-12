//
//  PostItLabelTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The chrome's words are typed labels the caller turns into strings (Ben's ruling on the
/// rev 2 look, 2026-10-11), so Penumbra can localize them and the layout measures what is
/// drawn. Woodcase's own renderer and CLI default to English.
struct PostItLabelTests {
    private func expansion(
        _ json: String, labels: @escaping (PenPostIt.Label) -> String = \.english
    ) throws -> PenPostItExpansion {
        try #require(PenPostIt.expansion(
            of: PostItExpansionTests.node(json), width: 240, height: 160,
            measure: PostItExpansionTests.measure, labels: labels
        ))
    }

    private static let queued = """
    {"id": "P1", "type": "prompt", "content": "Go", "model": "m",
     "metadata": {"woodcase": {"state": "queued", "requestedBy": "ben"}}}
    """

    @Test("The English labels are the mockup's words")
    func english() {
        #expect(PenPostIt.Label.promptTitle.english == "PROMPT")
        #expect(PenPostIt.Label.contextTitle.english == "CONTEXT")
        #expect(PenPostIt.Label.run.english == "Run")
        #expect(PenPostIt.Label.status(.queued, requestedBy: "ben").english == "Queued · ben")
        #expect(PenPostIt.Label.status(.running, requestedBy: nil).english == "Running")
        #expect(PenPostIt.Label.status(.done, requestedBy: "claude").english == "Done · claude")
    }

    @Test("Each chrome text part names its label")
    func partsCarryTheirLabel() throws {
        let prompt = try expansion(Self.queued)
        #expect(prompt.text(.header)?.label == .promptTitle)
        #expect(prompt.text(.runLabel)?.label == .run)
        #expect(prompt.text(.status)?.label == .status(.queued, requestedBy: "ben"))
        #expect(prompt.text(.modelLabel)?.label == nil, "a model name is data, not a label")
        let context = try expansion(#"{"id": "X1", "type": "context", "content": "Hi"}"#)
        #expect(context.text(.header)?.label == .contextTitle)
    }

    @Test("A label function localizes the chrome, and the layout measures the localized text")
    func localized() throws {
        let german: (PenPostIt.Label) -> String = { label in
            switch label {
            case .promptTitle: "AUFFORDERUNG"
            case .contextTitle: "KONTEXT"
            case .run: "Ausführen"
            case let .status(state, requestedBy): (state == .queued ? "Wartet" : state.rawValue) + (requestedBy.map { " – \($0)" } ?? "")
            }
        }
        let english = try expansion(Self.queued)
        let local = try expansion(Self.queued, labels: german)
        #expect(local.text(.header)?.string == "\u{25B6}\u{FE0E} AUFFORDERUNG")
        #expect(local.text(.runLabel)?.string == "\u{25B6}\u{FE0E} Ausführen")
        #expect(local.text(.status)?.string == "Wartet – ben")
        let englishButton = try #require(english.part(.runButton))
        let localButton = try #require(local.part(.runButton))
        #expect(localButton.frame.width > englishButton.frame.width, "the button fits the longer word")
    }

    @Test("No English word is left in the Style")
    func styleHoldsNoWords() {
        let mirror = Mirror(reflecting: PenPostIt.Style.standard)
        let strings = mirror.children.compactMap { $0.value as? String } + mirror.children.compactMap { $0.value as? [String] }.flatMap(\.self)
        let words = strings.filter { $0.contains(/[A-Za-z]{2,}/) && $0 != PenPostIt.Style.standard.labelFontFamily }
        #expect(words.isEmpty, "\(words)")
    }
}
