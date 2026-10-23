//
//  DocumentLinterConnectionStyleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `connection-style-ignored`: a connection whose `metadata.woodcase` routing or
/// arrowhead is not a spelling Woodcase draws, so it draws straight or bare instead. A
/// write refuses it; a file written by hand or by another tool is only told.
@MainActor
struct DocumentLinterConnectionStyleTests {
    private func findings(_ keys: String) throws -> [LintFinding] {
        let json = """
        {"version": "2.20", "children": [
          {"type": "rectangle", "id": "A", "x": 0, "y": 0, "width": 40, "height": 20},
          {"type": "rectangle", "id": "B", "x": 100, "y": 0, "width": 40, "height": 20},
          {"type": "connection", "id": "C", "name": "Link", "source": {"path": "A", "anchor": "right"},
           "target": {"path": "B", "anchor": "left"}, "stroke": "#000000",
           "metadata": {"type": "woodcase", "woodcase": \(keys)}}
        ]}
        """
        let document = try EditableDocument(from: PenParser.parse(json))
        return try DocumentLinter.findings(in: document).filter { $0.check == .connectionStyleIgnored }
    }

    @Test("An unknown routing is a warning naming the key, the value and the spellings")
    func unknownRouting() throws {
        let found = try findings(#"{"routing": "curved"}"#)
        let finding = try #require(found.first)
        #expect(found.count == 1)
        #expect(finding.nodeID == "C")
        #expect(finding.severity == .warning)
        #expect(finding.message.contains("kind.routing"), "\(finding.message)")
        #expect(finding.message.contains("curved"), "\(finding.message)")
        #expect(finding.message.contains("elbow"), "\(finding.message)")
    }

    @Test("Each unknown arrowhead is its own finding")
    func unknownArrowheads() throws {
        #expect(try findings(#"{"startArrowhead": "arrow", "endArrowhead": 3}"#).count == 2)
    }

    @Test("Known spellings are clean")
    func clean() throws {
        #expect(try findings(#"{"routing": "elbow", "startArrowhead": "none", "endArrowhead": "triangle"}"#).isEmpty)
    }
}
