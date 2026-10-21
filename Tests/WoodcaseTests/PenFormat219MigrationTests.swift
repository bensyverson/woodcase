//
//  PenFormat219MigrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers what reading a file older than 2.19 does to its shadows, the way Pen 1.2.14
/// does when it opens one: every inner shadow becomes an outer shadow — which is what
/// every earlier Pen drew — and `spread`, which 2.19 dropped, moves into
/// `metadata.woodcase.shadowSpread` (leaf zRp9CO). The conversion is said out loud, because
/// Pen says nothing.
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

    /// A pre-2.19 spread was deleted with a warning until leaf zRp9CO; it now moves into
    /// `metadata.woodcase.shadowSpread`, addressed to its effect and holding the migrated
    /// shadow, so the CG renderer draws it and a change in Pen makes it stale.
    @Test("A pre-2.19 spread moves into metadata.woodcase.shadowSpread, made for the migrated shadow")
    func legacySpreadIsKept() throws {
        let children = #"""
        [{"id":"R2","type":"rectangle","width":10,"height":10,
          "effect":{"type":"shadow","shadowType":"outer","color":"#000000","blur":4,"spread":6}}]
        """#
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        let node = try #require(doc.children.first)
        #expect(try shadow(of: node).extras.isEmpty)
        #expect(node.shadowSpread(forEffect: 0) == 6)
        let entry = try #require(node.shadowSpreads.first)
        #expect(try entry.shadow == shadow(of: node))
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("spread") })
        let written = try PenParser.encodeToString(doc)
        let reread = try PenParser.parse(Data(written.utf8))
        #expect(try shadow(of: #require(reread.children.first)).extras.isEmpty)
    }

    @Test("A spread on an inner shadow is made for the outer shadow it migrates to, so it still applies")
    func spreadFollowsTheInnerToOuterMigration() throws {
        let children = #"""
        [{"id":"R3","type":"rectangle","width":10,"height":10,
          "effect":[{"type":"blur","radius":2},{"type":"shadow","shadowType":"inner","blur":4,"spread":3}]}]
        """#
        let doc = try PenParser.parse(document(version: "2.17", children: children))
        let node = try #require(doc.children.first)
        #expect(node.shadowSpread(forEffect: 1) == 3)
        #expect(node.shadowSpreads.map(\.effect) == [1])
        #expect(node.shadowSpreads.first?.shadow.shadowType == .outer)
    }

    @Test("A zero spread draws nothing and is dropped silently")
    func zeroSpreadIsDropped() throws {
        let children = #"""
        [{"id":"R4","type":"rectangle","width":10,"height":10,"effect":{"type":"shadow","blur":4,"spread":0}}]
        """#
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        #expect(try #require(doc.children.first).common.metadata == nil)
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("spread") })
    }

    @Test("A spread naming a variable is discarded with a warning naming the node")
    func variableSpreadIsDiscarded() throws {
        let children = #"""
        [{"id":"R5","type":"rectangle","width":10,"height":10,"effect":{"type":"shadow","blur":4,"spread":"$s"}}]
        """#
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.17", children: children), diagnostics: diagnostics)
        #expect(try #require(doc.children.first).common.metadata == nil)
        let warning = try #require(diagnostics.diagnostics.first { $0.message.contains("spread") })
        #expect(warning.nodeID == "R5")
    }

    @Test("Spreads join the node's own metadata, keeping its type and keys")
    func spreadJoinsExistingMetadata() throws {
        let children = #"""
        [{"id":"R6","type":"rectangle","width":10,"height":10,"metadata":{"type":"card","owner":"ben"},
          "effect":{"type":"shadow","blur":4,"spread":2}}]
        """#
        let node = try #require(PenParser.parse(document(version: "2.17", children: children)).children.first)
        #expect(node.common.metadata?.type == "card")
        #expect(node.common.metadata?.extensions["owner"] == .string("ben"))
        #expect(node.shadowSpread(forEffect: 0) == 2)
    }

    /// Rule 6 merges an override's `metadata.woodcase` key by key over the component node's,
    /// so a spread in a bag with no metadata is kept, where it was once discarded.
    @Test("In an instance override with no metadata of its own, a spread is kept in new metadata")
    func spreadInBareOverrideIsKept() throws {
        let diagnostics = PenDiagnosticCollector()
        var bag: [String: AnyCodable] = ["effect": .dictionary(["type": "shadow", "blur": 4, "spread": 2])]
        PenShadowMigrationRule().apply(toNode: &bag, id: "inst/child", diagnostics: diagnostics)
        guard case let .dictionary(object)? = bag["metadata"] else {
            Issue.record("no metadata kept")
            return
        }
        let metadata = PenMetadata(object: object)
        #expect(metadata.type == PenMetadata.woodcaseType)
        let entries = try PenShadowSpread.entries(in: metadata[woodcase: .shadowSpread] ?? .null)
        #expect(entries.map(\.spread) == [2])
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("Discarded") })
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
