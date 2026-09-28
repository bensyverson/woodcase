//
//  BatchReportFormatterTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

@Suite("Rendering a batch report")
struct BatchReportFormatterTests {
    private func mixedReport() -> BatchReport {
        BatchReport(
            lines: [
                BatchLineResult(
                    line: 0, status: .applied,
                    created: [CreatedNode(id: "k2Bq9")], path: "Canvas/Hero"
                ),
                BatchLineResult(line: 1, status: .applied, path: "Canvas/Title"),
                BatchLineResult(line: 2, status: .failed, error: "boom"),
                BatchLineResult(line: 3, status: .cascaded, error: "skipped: it depends on line 2"),
            ],
            documentRevision: "abc123"
        )
    }

    @Test("Each line's row lines up in fixed columns, then a summary carries the revision")
    func textRendersColumnarRows() {
        let expected = """
        line 0  applied  Canvas/Hero  k2Bq9
        line 1  applied  Canvas/Title
        line 2  failed   boom
        line 3  cascaded skipped: it depends on line 2
        2 applied, 1 failed, 1 cascaded — revision abc123
        """
        #expect(BatchReportFormatter.text(mixedReport()) == expected)
    }

    @Test("A document-level line with no path falls back to 'document'")
    func textFallsBackToDocumentForPathlessLines() {
        let report = BatchReport(
            lines: [BatchLineResult(line: 0, status: .applied)],
            documentRevision: "rev1"
        )
        #expect(BatchReportFormatter.text(report) == """
        line 0  applied  document
        1 applied, 0 failed, 0 cascaded — revision rev1
        """)
    }

    @Test("An empty batch still renders its summary")
    func textRendersEmptyBatch() {
        let report = BatchReport(lines: [], documentRevision: "rev0")
        #expect(BatchReportFormatter.text(report) == "0 applied, 0 failed, 0 cascaded — revision rev0")
    }

    @Test("JSON output decodes back to an equal report, so --retry can read it")
    func jsonRoundTrips() throws {
        let report = mixedReport()
        let data = try Data(BatchReportFormatter.json(report).utf8)
        let decoded = try JSONDecoder().decode(BatchReport.self, from: data)
        #expect(decoded == report)
    }

    @Test("JSON output sorts its keys")
    func jsonSortsKeys() throws {
        let text = try BatchReportFormatter.json(mixedReport())
        let atomicIndex = try #require(text.range(of: "\"atomic\""))
        let linesIndex = try #require(text.range(of: "\"lines\""))
        #expect(atomicIndex.lowerBound < linesIndex.lowerBound)
    }

    // MARK: - The divergence echo

    /// The golden for the quiet case: a line that stored exactly what it was handed
    /// renders the byte-for-byte row it rendered before the echo existed, whatever
    /// else the result now carries.
    @Test("An applied line that diverged from nothing renders exactly the row it always did")
    func agreementRendersTheOldRow() {
        let report = BatchReport(
            lines: [BatchLineResult(
                line: 0, status: .applied, path: "Canvas/Title",
                id: "Ttl01",
                node: PenNode(id: "Ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData())),
                divergences: []
            )],
            documentRevision: "abc123"
        )

        #expect(BatchReportFormatter.text(report) == """
        line 0  applied  Canvas/Title
        1 applied, 0 failed, 0 cascaded — revision abc123
        """)
    }

    @Test("A divergence rides under its own row, indented clear of the line gutter")
    func divergenceRendersUnderItsRow() {
        let report = BatchReport(
            lines: [BatchLineResult(
                line: 0, status: .applied, path: "Canvas/Title", id: "Ttl01",
                divergences: [
                    WriteDivergence(
                        kind: .coercion, target: "kind.content",
                        requested: "3", applied: "\"3\"",
                        note: "kind.content stored the number 3 as the text \"3\""
                    ),
                    WriteDivergence(
                        kind: .variableReference, target: "kind.fontFamily",
                        requested: "$brand", applied: "the string variable brand",
                        note: "kind.fontFamily resolved $brand as a reference"
                    ),
                ]
            )],
            documentRevision: "abc123"
        )

        #expect(BatchReportFormatter.text(report) == """
        line 0  applied  Canvas/Title
                kind.content stored the number 3 as the text "3"
                kind.fontFamily resolved $brand as a reference
        1 applied, 0 failed, 0 cascaded — revision abc123
        """)
    }
}
