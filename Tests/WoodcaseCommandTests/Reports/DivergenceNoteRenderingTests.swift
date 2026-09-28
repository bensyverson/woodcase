//
//  DivergenceNoteRenderingTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// How the two tiers of ``WriteDivergence`` read in a report.
///
/// A divergence says the stored form means something other than the plain reading of
/// the write; a note says the write means exactly what it says and states one fact
/// about it. The note is marked so it cannot be mistaken for the warning.
struct DivergenceNoteRenderingTests {
    private var note: WriteDivergence {
        WriteDivergence(
            kind: .unsetOverrideProperty,
            severity: .note,
            target: "enabled",
            requested: "an override of enabled",
            applied: "a value added to Card1/Title",
            note: "Card1/Title adds enabled rather than replacing it"
        )
    }

    private var divergence: WriteDivergence {
        WriteDivergence(
            kind: .coercion, target: "kind.content", requested: "3", applied: "\"3\"",
            note: "kind.content stored the number 3 as the text \"3\""
        )
    }

    @Test("A write's note is marked; its divergence keeps the bytes it always had")
    func writeReportMarksTheNote() {
        let report = WriteReport(
            path: "Canvas/Card1",
            id: "Card1",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222",
            divergences: [divergence, note]
        )

        #expect(report.text == """
        Canvas/Card1  Card1
        kind.content stored the number 3 as the text "3"
        note  Card1/Title adds enabled rather than replacing it
        rev  1111111111111111
        document  2222222222222222
        """)
    }

    @Test("A batch line's note is marked under its own row")
    func batchReportMarksTheNote() {
        let report = BatchReport(
            lines: [BatchLineResult(
                line: 0, status: .applied, path: "Canvas/Card1", id: "Card1",
                divergences: [note]
            )],
            documentRevision: "abc123"
        )

        #expect(BatchReportFormatter.text(report) == """
        line 0  applied  Canvas/Card1
                note  Card1/Title adds enabled rather than replacing it
        1 applied, 0 failed, 0 cascaded — revision abc123
        """)
    }

    @Test("--json carries the severity, so a caller branches without reading the sentence")
    func jsonCarriesTheSeverity() throws {
        let report = WriteReport(
            path: "Canvas/Card1",
            id: "Card1",
            documentRevision: "2222222222222222",
            divergences: [note]
        )

        let decoded = try JSONDecoder().decode(
            WriteReport.self, from: Data(report.json().utf8)
        )
        #expect(decoded.divergences?.first?.severity == .note)
    }

    @Test("A divergence made without saying is the loud tier")
    func severityDefaultsToDivergence() {
        #expect(divergence.severity == .divergence)
    }
}
