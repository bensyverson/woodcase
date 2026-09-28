//
//  DocumentLinterTextStrippedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `text-style-stripped`: a text node carrying a stroke, an underline or a
/// strikethrough, which Pen strips when it opens the file and never draws.
///
/// Pen's behaviour was confirmed in Pen.app 1.2.14 and the headless `pen` CLI
/// (`project/2026-09-26-what-pen-drops-from-a-file.md`); these tests hold the lint to
/// it, and never run Pen.
@MainActor
struct DocumentLinterTextStrippedTests {
    // MARK: - Helpers

    /// A document whose one root is a frame holding a text node with `keys` added.
    private func board(text keys: String, variables: String = "{}") throws -> EditableDocument {
        let json = """
        {"version": "2.17", "variables": \(variables), "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "x": 0, "y": 0,
           "width": 400, "height": 200, "layout": "none", "children": [
             {"type": "text", "id": "Txt01", "name": "Label", "x": 0, "y": 0,
              "content": "Hello", "fontSize": 16, "fill": "#000000"\(keys)}
          ]}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(json))
    }

    private func stripped(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .textStyleStripped }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is text-style-stripped")
    func checkIsAWarning() {
        #expect(LintCheck.textStyleStripped.rawValue == "text-style-stripped")
        #expect(LintCheck.textStyleStripped.severity == .warning)
        #expect(!LintCheck.textStyleStripped.summary.isEmpty)
    }

    // MARK: - One finding per case

    @Test("A stroke on text is a finding naming every stroke key it carries")
    func stroke() throws {
        let doc = try board(text: ##", "stroke": "#FF0000", "strokeWidth": 4, "strokeAlignment": "outer""##)
        let found = try stripped(doc)
        #expect(found.count == 1)
        let finding = try #require(found.first)
        #expect(finding.nodeID == "Txt01")
        #expect(finding.message.contains("stroke, strokeWidth, strokeAlignment"))
        #expect(finding.message.contains("Pen"))
    }

    @Test("An underline is a finding, and says Woodcase still draws it")
    func underline() throws {
        let found = try stripped(board(text: #", "underline": true"#))
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("underline"))
        #expect(message.contains("Woodcase draws"))
    }

    @Test("A strikethrough is a finding, and says Woodcase still draws it")
    func strikethrough() throws {
        let found = try stripped(board(text: #", "strikethrough": true"#))
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("strikethrough"))
        #expect(message.contains("Woodcase draws"))
    }

    @Test("All three on one node are three findings")
    func allThree() throws {
        let doc = try board(text: ##", "stroke": "#FF0000", "underline": true, "strikethrough": true"##)
        #expect(try stripped(doc).count == 3)
    }

    @Test("An underline held in a variable is judged on the value it resolves to")
    func variableUnderline() throws {
        let variables = #"{"decorated": {"type": "boolean", "value": true}}"#
        let found = try stripped(board(text: #", "underline": "$decorated""#, variables: variables))
        #expect(found.count == 1)
    }

    @Test("underline: false and strikethrough: false lose nothing, and are clean")
    func falseIsClean() throws {
        let doc = try board(text: #", "underline": false, "strikethrough": false"#)
        #expect(try stripped(doc).isEmpty)
    }

    @Test("A stroke on a non-text node is not this check's business")
    func rectangleStrokeIsClean() throws {
        let json = ##"""
        {"version": "2.17", "children": [
          {"type": "rectangle", "id": "Rct01", "name": "Box", "x": 0, "y": 0,
           "width": 40, "height": 40, "stroke": "#FF0000", "strokeWidth": 2}
        ]}
        """##
        #expect(try stripped(EditableDocument(from: PenParser.parse(json))).isEmpty)
    }
}
