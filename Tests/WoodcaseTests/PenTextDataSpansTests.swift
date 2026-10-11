//
//  PenTextDataSpansTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A text node's spans on the model: which runs apply to its content, and that the format's
/// own encoding never carries them (Pen deletes a run array in `content`; their storage is
/// the `woodcase.spans` metadata key, not the node's own keys).
struct PenTextDataSpansTests {
    private static let bold = [PenTextRun(start: 10, end: 14, fontWeight: 700)]

    @Test("A text node's spans apply only while made for its literal content")
    func appliedOnlyWhenMatching() {
        let spans = PenTextSpans(text: "Make this bold", runs: Self.bold)
        #expect(PenNode.TextData(content: .literal("Make this bold"), spans: spans).appliedRuns == Self.bold)
        #expect(PenNode.TextData(content: .literal("Make this bold, please"), spans: spans).appliedRuns.isEmpty)
        #expect(PenNode.TextData(content: .literal("Make this bold")).appliedRuns.isEmpty)
        let variable = PenTextSpans(text: "$headline", runs: Self.bold)
        #expect(PenNode.TextData(content: .variable("headline"), spans: variable).appliedRuns.isEmpty)
    }

    @Test("The format's encoding of a text node never writes its spans")
    func notEncoded() throws {
        let data = PenNode.TextData(
            content: .literal("Make this bold"),
            spans: PenTextSpans(text: "Make this bold", runs: Self.bold)
        )
        let json = try #require(String(data: JSONEncoder().encode(data), encoding: .utf8))
        #expect(!json.contains("spans"))
        #expect(!json.contains("runs"))
        #expect(json.contains("\"content\":\"Make this bold\""))
    }
}
