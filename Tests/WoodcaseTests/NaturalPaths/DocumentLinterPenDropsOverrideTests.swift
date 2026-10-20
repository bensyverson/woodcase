//
//  DocumentLinterPenDropsOverrideTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `pen-drops-override`: an instance that overrides a Woodcase-owned key — in a
/// `descendants` override's `metadata.woodcase`, or on its own `ref` node, its lock among
/// them — which Pen drops when it saves the file (pen CLI, leaf 9Sw8C0). One notice per
/// instance, listing the keys; nothing to fix (Ben's ruling, 2026-10-20).
@MainActor
struct DocumentLinterPenDropsOverrideTests {
    private func findings(_ ref: String) throws -> [LintFinding] {
        let json = """
        {"version": "2.20", "children": [
          {"type": "frame", "id": "Cmp01", "name": "Badge", "reusable": true, "width": 40, "height": 40,
           "layout": "none", "stroke": "#000000", "strokeWidth": 1, "children": [
            {"type": "rectangle", "id": "Box01", "name": "Box", "width": 10, "height": 10,
             "stroke": "#000000", "strokeWidth": 1}
          ]},
          \(ref)
        ]}
        """
        return try DocumentLinter.findings(in: EditableDocument(from: PenParser.parse(json)))
            .filter { $0.check == .penDropsOverride }
    }

    @Test("One notice per instance names every Woodcase-owned key it overrides, its own lock included")
    func onePerInstance() throws {
        let found = try findings("""
        {"type": "ref", "id": "Ins01", "name": "Inst", "ref": "Cmp01", "x": 100,
         "metadata": {"type": "woodcase", "woodcase": {"locked": true, "strokeDash": [4, 2]}},
         "descendants": {"Box01": {"metadata": {"type": "woodcase", "woodcase": {"blendMode": "screen",
           "strokeMiterLimit": 2}}}}}
        """)
        let finding = try #require(found.first)
        #expect(found.count == 1)
        #expect(finding.nodeID == "Ins01")
        #expect(finding.severity == .notice)
        for named in ["common.locked", "kind.strokeDash", "Box kind.blendMode", "Box kind.strokeMiterLimit"] {
            #expect(finding.message.contains(named), "\(named): \(finding.message)")
        }
        #expect(finding.message.contains("Pen"), "\(finding.message)")
    }

    @Test("An instance overriding only the format's own keys, or nothing, is clean")
    func clean() throws {
        #expect(try findings("""
        {"type": "ref", "id": "Ins01", "ref": "Cmp01", "descendants": {"Box01": {"fill": "#FF0000"}}}
        """).isEmpty)
        #expect(try findings(#"{"type": "ref", "id": "Ins01", "ref": "Cmp01"}"#).isEmpty)
    }

    @Test("The check is a notice")
    func severity() {
        #expect(LintCheck.penDropsOverride.severity == .notice)
        #expect(LintCheck.penDropsOverride.rawValue == "pen-drops-override")
    }
}
