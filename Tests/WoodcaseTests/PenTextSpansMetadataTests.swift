//
//  PenTextSpansMetadataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Spans as `metadata.woodcase.spans` stores them: the wire form, the one accessor, and the
/// runs a text node reads from its own metadata. Imported without `@testable`: RapidPro and
/// Penumbra read spans through exactly this surface.
struct PenTextSpansMetadataTests {
    private static let red = PenHexColor(red: 255, green: 0, blue: 0)

    private static let spans = PenTextSpans(text: "Make this bold", runs: [
        PenTextRun(
            start: 10, end: 14, fontFamily: "Inter", fontSize: 20, fontWeight: 700, isItalic: true,
            fill: red, underline: true, strikethrough: false
        ),
        PenTextRun(start: 0, end: 4, isItalic: false, fill: PenHexColor(red: 0, green: 0, blue: 255, alpha: 128)),
    ])

    /// The wire form of ``spans``, as the file writes it.
    private static let wire: AnyCodable = .dictionary([
        "text": .string("Make this bold"),
        "runs": .array([
            .dictionary([
                "start": .int(10), "end": .int(14), "fontFamily": .string("Inter"), "fontSize": .int(20),
                "fontWeight": .string("700"), "fontStyle": .string("italic"), "fill": .string("#FF0000"),
                "underline": .bool(true), "strikethrough": .bool(false),
            ]),
            .dictionary([
                "start": .int(0), "end": .int(4), "fontStyle": .string("normal"), "fill": .string("#0000FF80"),
            ]),
        ]),
    ])

    @Test("Spans write the wire form: hex fills, the format's weight and style strings")
    func writesTheWireForm() {
        #expect(Self.spans.metadataValue == Self.wire)
    }

    @Test("The wire form reads back to the same spans")
    func readsTheWireForm() throws {
        #expect(try PenTextSpans(metadataValue: Self.wire) == Self.spans)
    }

    @Test("A weight keyword and a fractional size read as their numbers")
    func readsKeywordsAndFractions() throws {
        let value: AnyCodable = .dictionary([
            "text": .string("ab"),
            "runs": .array([.dictionary([
                "start": .int(0), "end": .int(2), "fontWeight": .string("semibold"), "fontSize": .double(13.5),
            ])]),
        ])
        let spans = try PenTextSpans(metadataValue: value)
        #expect(spans.runs == [PenTextRun(start: 0, end: 2, fontSize: 13.5, fontWeight: 600)])
    }

    @Test("Malformed spans are refused with a reason", arguments: [
        AnyCodable.string("bold"),
        .dictionary(["runs": .array([])]),
        .dictionary(["text": .string("ab"), "runs": .string("x")]),
        .dictionary(["text": .string("ab"), "runs": .array([]), "extra": .bool(true)]),
        .dictionary(["text": .string("ab"), "runs": .array([.dictionary(["end": .int(1)])])]),
        .dictionary(["text": .string("ab"), "runs": .array([.dictionary(["start": .int(0), "end": .int(3)])])]),
        .dictionary(["text": .string("ab"), "runs": .array([.dictionary(["start": .int(2), "end": .int(1)])])]),
        .dictionary(["text": .string("ab"), "runs": .array([.dictionary(["start": .int(-1), "end": .int(1)])])]),
        .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "fontWeight": .string("heaviest")]),
        ])]),
        .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "fill": .string("red")]),
        ])]),
        .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "fontStyle": .string("oblique")]),
        ])]),
        .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "fontSize": .int(0)]),
        ])]),
        .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "bold": .bool(true)]),
        ])]),
    ])
    func refusesMalformed(value: AnyCodable) {
        #expect(throws: PenTextSpans.WireError.self) { try PenTextSpans(metadataValue: value) }
    }

    @Test("A refusal names what is wrong")
    func refusalNamesTheProblem() {
        let value: AnyCodable = .dictionary(["text": .string("ab"), "runs": .array([
            .dictionary(["start": .int(0), "end": .int(1), "bold": .bool(true)]),
        ])])
        #expect {
            try PenTextSpans(metadataValue: value)
        } throws: { error in
            "\(error)".contains("bold")
        }
    }

    @Test("Spans are read and written through the namespace accessor, typing new metadata")
    func metadataAccessor() {
        var metadata = PenMetadata(type: nil)
        metadata.textSpans = Self.spans
        #expect(metadata[woodcase: .spans] == Self.wire)
        #expect(metadata.type == PenMetadata.woodcaseType)
        #expect(metadata.textSpans == Self.spans)
        metadata.textSpans = nil
        #expect(metadata[woodcase: .spans] == nil)
    }

    @Test("Unreadable stored spans read as none")
    func unreadableReadsAsNone() {
        var metadata = PenMetadata(type: "woodcase")
        metadata[woodcase: .spans] = .string("bold")
        #expect(metadata.textSpans == nil)
    }

    private static func node(content: PenValue<String>, spans: PenTextSpans?) -> PenNode {
        var metadata: PenMetadata?
        if let spans {
            var written = PenMetadata(type: nil)
            written.textSpans = spans
            metadata = written
        }
        return PenNode(id: "t", common: PenNodeCommon(metadata: metadata), kind: .text(PenNode.TextData(content: content)))
    }

    @Test("A text node applies its spans only while made for its literal content")
    func nodeAppliedRuns() {
        let bold = [PenTextRun(start: 10, end: 14, fontWeight: 700)]
        let spans = PenTextSpans(text: "Make this bold", runs: bold)
        #expect(Self.node(content: .literal("Make this bold"), spans: spans).appliedRuns == bold)
        #expect(Self.node(content: .literal("Make this bold!"), spans: spans).appliedRuns.isEmpty)
        #expect(Self.node(content: .literal("Make this bold"), spans: nil).appliedRuns.isEmpty)
        #expect(Self.node(content: .variable("headline"), spans: PenTextSpans(text: "$headline", runs: bold))
            .appliedRuns.isEmpty)
        let rect = PenNode(id: "r", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        #expect(rect.appliedRuns.isEmpty)
    }

    @Test("A text node knows when its spans are stale")
    func nodeStaleSpans() {
        let spans = PenTextSpans(text: "Make this bold", runs: [PenTextRun(start: 0, end: 4, fontWeight: 700)])
        #expect(Self.node(content: .literal("Make this bold!"), spans: spans).hasStaleTextSpans)
        #expect(!Self.node(content: .literal("Make this bold"), spans: spans).hasStaleTextSpans)
        #expect(!Self.node(content: .literal("Make this bold"), spans: nil).hasStaleTextSpans)
    }
}
