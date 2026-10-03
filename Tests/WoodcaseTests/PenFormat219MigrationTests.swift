//
//  PenFormat219MigrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers what reading a file older than 2.19 does to its shadows, the way Pen 1.2.14
/// does when it opens one: every inner shadow becomes an outer shadow — which is what
/// every earlier Pen drew — and `spread`, which 2.19 dropped, is deleted. Both are said
/// out loud, because Pen says nothing.
struct PenFormat219MigrationTests {
    // MARK: - Helpers

    private func document(version: String, children: String) -> Data {
        Data(#"{"version":"\#(version)","children":\#(children)}"#.utf8)
    }

    private func shadow(of node: PenNode, at index: Int = 0) throws -> PenEffect.PenShadowEffect {
        guard case let .rectangle(data) = node.kind else {
            Issue.record("\(node.id) is not a rectangle")
            throw CancellationError()
        }
        let effects: [PenEffect] = switch data.effects {
        case let .single(effect)?: [effect]
        case let .multiple(effects)?: effects
        case nil: []
        }
        guard case let .shadow(shadow) = effects[index] else {
            Issue.record("effect \(index) of \(node.id) is not a shadow")
            throw CancellationError()
        }
        return shadow
    }

    private let innerShadowRectangle = #"""
    [{"id":"R1","type":"rectangle","width":10,"height":10,
      "effect":{"type":"shadow","shadowType":"inner","color":"#000000","blur":4}}]
    """#

    // MARK: - The version

    @Test("A 2.17 file with nothing to migrate reads without a diagnostic and reports the model's version")
    func plain217ReadsQuietly() throws {
        let diagnostics = PenDiagnosticCollector()
        let children = #"[{"id":"R1","type":"rectangle","width":10,"height":10,"strokeAlignment":"inner"}]"#
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    // MARK: - Inner shadows

    @Test("A pre-2.19 inner shadow reads as an outer shadow, with a warning naming the node",
          arguments: ["2.17", "2.18", "2.11"])
    func legacyInnerBecomesOuter(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: innerShadowRectangle), diagnostics: diagnostics)
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .outer)
        let warning = try #require(diagnostics.diagnostics.first { $0.message.contains("inner") })
        #expect(warning.severity == .warning)
        #expect(warning.stage == .migration)
        #expect(warning.nodeID == "R1")
    }

    @Test("A 2.9 legacy inner shadow is migrated to outer too")
    func legacy29InnerBecomesOuter() throws {
        let doc = try PenParser.parse(document(version: "2.9", children: innerShadowRectangle))
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .outer)
    }

    @Test("A 2.19 inner shadow stays inner, silently")
    func current219InnerStaysInner() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.19", children: innerShadowRectangle), diagnostics: diagnostics)
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).shadowType == .inner)
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics)")
    }

    @Test("Only the inner shadow of an [outer, inner] array changes")
    func onlyInnerInArrayChanges() throws {
        let children = #"""
        [{"id":"R1","type":"rectangle","width":10,"height":10,"effect":[
          {"type":"shadow","shadowType":"outer","color":"#00000080","blur":16},
          {"type":"shadow","shadowType":"inner","color":"#FFFF00FF","blur":6},
          {"type":"blur","radius":2}]}]
        """#
        let doc = try PenParser.parse(document(version: "2.17", children: children))
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node, at: 0).shadowType == .outer)
        #expect(try shadow(of: node, at: 1).shadowType == .outer)
    }

    @Test("An inner shadow inside a ref's descendant override is migrated")
    func innerInDescendantOverrideMigrates() throws {
        let children = #"""
        [{"id":"C","type":"frame","reusable":true,"width":20,"height":20,
          "children":[{"id":"K","type":"rectangle","width":10,"height":10}]},
         {"id":"I","type":"ref","ref":"C","descendants":{"K":{
           "effect":{"type":"shadow","shadowType":"inner","color":"#000000","blur":2}}}}]
        """#
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        let instance = try #require(doc.children.last)
        guard case let .ref(data) = instance.kind else {
            Issue.record("I is not a ref")
            return
        }
        let override = try #require(data.descendants?["K"])
        let effect = try #require(override.properties["effect"])
        #expect(effect == ["type": "shadow", "shadowType": "outer", "color": "#000000", "blur": 2])
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "K" })
    }

    // MARK: - Spread

    @Test("A pre-2.19 spread is deleted, with a warning naming the node")
    func legacySpreadIsDropped() throws {
        let children = #"""
        [{"id":"R2","type":"rectangle","width":10,"height":10,
          "effect":{"type":"shadow","shadowType":"outer","color":"#000000","blur":4,"spread":6}}]
        """#
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).extras.isEmpty)
        let written = try PenParser.encodeToString(doc)
        #expect(!written.contains("spread"))
        let warning = try #require(diagnostics.diagnostics.first { $0.message.contains("spread") })
        #expect(warning.nodeID == "R2")
        #expect(warning.severity == .warning)
    }

    @Test("Migration is idempotent: re-reading the written file changes nothing more")
    func migrationIsIdempotent() throws {
        let first = PenDiagnosticCollector()
        let once = try PenParser.parse(document(version: "2.17", children: innerShadowRectangle), diagnostics: first)
        #expect(first.diagnostics.count == 1, "the first read migrates, and says so once")
        let second = PenDiagnosticCollector()
        let twice = try PenParser.parse(PenParser.encode(once), diagnostics: second)
        #expect(twice == once)
        #expect(twice.version == PenDocument.currentFormatVersion)
        #expect(second.diagnostics.isEmpty)
    }
}
