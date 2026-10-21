//
//  DocumentLinterShadowSpreadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `shadow-spread-stale`: a node's `metadata.woodcase.shadowSpread` entry made for a shadow
/// the node no longer has at that place — Pen, which keeps metadata but cannot see it,
/// changed or moved the effect — so the shadow casts without its spread (leaf zRp9CO).
@MainActor
struct DocumentLinterShadowSpreadTests {
    private static let shadow = ##"{"type": "shadow", "blur": 8, "color": "#000000"}"##

    private func findings(effect: String, madeFor: String = Self.shadow) throws -> [LintFinding] {
        let json = """
        {"version": "2.19", "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "x": 0, "y": 0, "width": 400, "height": 200,
           "layout": "none", "children": [
            {"type": "rectangle", "id": "Rct01", "name": "Card", "width": 100, "height": 60, "fill": "#FFFFFF",
             "effect": \(effect),
             "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 4, "shadow": \(madeFor)}]}}}
          ]}
        ]}
        """
        let document = try EditableDocument(from: PenParser.parse(json))
        return try DocumentLinter.findings(in: document).filter { $0.check == .shadowSpreadStale }
    }

    @Test("A spread whose shadow changed is a warning that it casts without it, naming the way out")
    func staleSpreadIsReported() throws {
        let found = try findings(effect: ##"{"type": "shadow", "blur": 12, "color": "#000000"}"##)
        let finding = try #require(found.first)
        #expect(found.count == 1)
        #expect(finding.nodeID == "Rct01")
        #expect(finding.check.severity == .warning)
        #expect(finding.message.contains("effect 0"), "\(finding.message)")
        // The way out is a write of kind.effects with spread on the shadow; the storage path
        // is no longer a way in (leaf oNeklc).
        #expect(finding.message.contains("`kind.effects`"), "\(finding.message)")
        #expect(!finding.message.contains(PenMetadata.WoodcaseKey.shadowSpread.path), "\(finding.message)")
    }

    @Test("A spread made for the shadow it addresses is clean")
    func freshSpreadIsClean() throws {
        #expect(try findings(effect: Self.shadow).isEmpty)
    }
}
