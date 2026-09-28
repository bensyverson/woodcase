//
//  BatchThemedVariableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The `var` op carrying a themed value: the bulk route for a token layer.
///
/// A themed value decoded before this suite existed, but the axes it named were never
/// registered — so a batch could leave a document whose variables pin `mode=dark` and
/// whose `themes` table has no `mode` at all, which `vars set --theme` can never
/// produce. The registration rule is the one `vars set --theme` states: an axis the
/// document lacks is created, an option an axis lacks is appended.
@MainActor
struct BatchThemedVariableTests {
    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func apply(_ jsonl: String, to document: EditableDocument) throws -> BatchReport {
        try BatchApplier.apply(BatchOperation.decodeJSONL(jsonl), to: document)
    }

    /// Criterion xbX.
    @Test("A themed var line registers the axis it names, creating it")
    func themedLineCreatesTheAxis() throws {
        let doc = try makeDocument()
        let report = try apply(
            ##"{"op":"var","name":"accent","value":{"type":"color","value":[{"value":"#fff","theme":{"mode":"light"}},{"value":"#000","theme":{"mode":"dark"}}]}}"##,
            to: doc
        )
        #expect(report.lines[0].status == .applied)
        #expect(doc.themes?["mode"] == ["light", "dark"], "the axis the line named was not registered")
    }

    @Test("A themed var line appends an option the axis lacks, keeping the order")
    func themedLineAppendsAMissingOption() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"theme-axis","name":"mode","options":["light","dark"]}
        {"op":"var","name":"accent","value":{"type":"color","value":[{"value":"#000","theme":{"mode":"dark"}},{"value":"#777","theme":{"mode":"dim"}}]}}
        """, to: doc)
        #expect(report.lines.map(\.status) == [.applied, .applied])
        #expect(doc.themes?["mode"] == ["light", "dark", "dim"], "the option was not appended in order")
    }

    /// Criterion xbX.
    @Test("The divergence echo on a themed line shows every option's value")
    func divergenceShowsBothOptions() throws {
        let doc = try makeDocument()
        let report = try apply(
            ##"{"op":"var","name":"accent","value":{"type":"color","value":[{"value":"#fff","theme":{"mode":"light"}},{"value":"#000","theme":{"mode":"dark"}}]}}"##,
            to: doc
        )
        let note = try #require(report.lines[0].divergences.first?.note, "a themed line echoed nothing")
        #expect(note.contains("mode=light"), "the light option is missing from the echo: \(note)")
        #expect(note.contains("#fff"), "the light option's value is missing from the echo: \(note)")
        #expect(note.contains("mode=dark"), "the dark option is missing from the echo: \(note)")
        #expect(note.contains("#000"), "the dark option's value is missing from the echo: \(note)")
    }

    @Test("A plain var line echoes nothing")
    func plainLineEchoesNothing() throws {
        let doc = try makeDocument()
        let report = try apply(
            ##"{"op":"var","name":"brand","value":{"type":"color","value":"#ff0000"}}"##,
            to: doc
        )
        #expect(report.lines[0].divergences.isEmpty, "a plain var line carried a divergence")
    }

    @Test("A whole token layer goes through one batch, axes and all")
    func aTokenLayerGoesThroughOneBatch() throws {
        let doc = try makeDocument()
        let lines = (1 ... 17).map { index in
            let light = String(format: "#%02x%02x%02x", index * 5, 200, 200)
            let dark = String(format: "#%02x%02x%02x", index * 5, 40, 40)
            return #"{"op":"var","name":"t\#(index)","value":{"type":"color","value":"#
                + #"[{"value":"\#(light)","theme":{"mode":"light"}},"#
                + #"{"value":"\#(dark)","theme":{"mode":"dark"}}]}}"#
        }
        let report = try apply(lines.joined(separator: "\n"), to: doc)
        #expect(report.lines.allSatisfy { $0.status == .applied })
        #expect(doc.variables?.count == 17)
        #expect(doc.themes?["mode"] == ["light", "dark"], "17 lines registered the axis more than once")
    }
}
