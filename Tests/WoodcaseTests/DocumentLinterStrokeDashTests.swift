//
//  DocumentLinterStrokeDashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `stroke-dash-ignored`: a file's `metadata.woodcase.strokeDash` that every target draws
/// solid — on a per-side stroke, whose bands dashes cannot flow around, or a dash no target
/// can draw (a negative length, all zeros, more than 16 lengths, not numbers). A write is
/// refused all of these; a file is only told.
@MainActor
struct DocumentLinterStrokeDashTests {
    private func findings(width: String = "2", dash: String) throws -> [LintFinding] {
        let json = """
        {"version": "2.19", "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "x": 0, "y": 0, "width": 400, "height": 200,
           "layout": "none", "children": [
            {"type": "rectangle", "id": "Rct01", "name": "Card", "width": 100, "height": 60, "stroke": "#000000",
             "strokeWidth": \(width), "metadata": {"type": "woodcase", "woodcase": {"strokeDash": \(dash)}}}
          ]}
        ]}
        """
        let document = try EditableDocument(from: PenParser.parse(json))
        return try DocumentLinter.findings(in: document).filter { $0.check == .strokeDashIgnored }
    }

    @Test("A dash on a per-side stroke is a warning that it draws solid")
    func perSide() throws {
        let found = try findings(width: #"{"top": 2, "bottom": 4}"#, dash: "[8, 4]")
        let finding = try #require(found.first)
        #expect(found.count == 1)
        #expect(finding.nodeID == "Rct01")
        #expect(finding.severity == .warning)
        #expect(finding.message.contains("per-side"), "\(finding.message)")
        #expect(finding.message.contains("solid"), "\(finding.message)")
    }

    @Test("A dash no target can draw is a warning that it draws solid, saying why",
          arguments: ["[-2, 4]", "[0, 0]", "[\(Array(repeating: "1", count: 17).joined(separator: ", "))]", #""8 4""#])
    func malformed(dash: String) throws {
        let finding = try #require(try findings(dash: dash).first)
        #expect(finding.message.contains("solid"), "\(finding.message)")
    }

    @Test("A well-formed dash on a uniform stroke, or an empty one anywhere, is clean")
    func clean() throws {
        #expect(try findings(dash: "[8, 4]").isEmpty)
        #expect(try findings(width: #"{"top": 2}"#, dash: "[]").isEmpty)
    }
}
