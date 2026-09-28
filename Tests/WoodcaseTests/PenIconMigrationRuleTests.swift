//
//  PenIconMigrationRuleTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Tests for the migrator rule that rewrites a legacy `icon_font` node into the
/// 2.17 `icon` shape: `type: "icon_font"` → `"icon"`, `iconFontFamily` → `library`,
/// `iconFontName` → `icon`. `weight` and `fill` carry over unchanged, and nothing
/// is discarded, so the rule must never emit a diagnostic.
struct PenIconMigrationRuleTests {
    private func iconNode(
        id: String = "icon1",
        family: String = "lucide",
        name: String = "bell",
        weight: Double? = nil,
        fill: String? = "#000000"
    ) -> [String: AnyCodable] {
        var node: [String: AnyCodable] = [
            "id": .string(id),
            "type": .string("icon_font"),
            "iconFontFamily": .string(family),
            "iconFontName": .string(name),
        ]
        if let weight { node["weight"] = .double(weight) }
        if let fill { node["fill"] = .string(fill) }
        return node
    }

    // MARK: - Node rewriting

    @Test("Rewrites the type and both keys")
    func rewritesTypeAndKeys() {
        var node = iconNode()
        PenIconMigrationRule().apply(toNode: &node, id: "icon1", diagnostics: nil)
        #expect(node["type"] == .string("icon"))
        #expect(node["icon"] == .string("bell"))
        #expect(node["library"] == .string("lucide"))
        #expect(node["iconFontFamily"] == nil)
        #expect(node["iconFontName"] == nil)
    }

    @Test("Leaves weight and fill unchanged")
    func leavesWeightAndFillUnchanged() {
        var node = iconNode(weight: 700, fill: "#9accffff")
        PenIconMigrationRule().apply(toNode: &node, id: "icon1", diagnostics: nil)
        #expect(node["weight"] == .double(700))
        #expect(node["fill"] == .string("#9accffff"))
    }

    @Test("Leaves a non-icon node untouched")
    func leavesOtherNodesUntouched() {
        var node: [String: AnyCodable] = ["id": .string("r1"), "type": .string("rectangle")]
        let before = node
        PenIconMigrationRule().apply(toNode: &node, id: "r1", diagnostics: nil)
        #expect(node == before)
    }

    @Test("Discards nothing, so no diagnostic is emitted")
    func emitsNoDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = iconNode(weight: 400)
        PenIconMigrationRule().apply(toNode: &node, id: "icon1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    // MARK: - Traversal (through PenLegacyMigrator)

    @Test("Rewrites an icon_font node nested under a frame's children")
    func rewritesNestedChild() {
        let tree: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([
                .dictionary([
                    "id": .string("root1"),
                    "type": .string("frame"),
                    "children": .array([.dictionary(iconNode())]),
                ]),
            ]),
        ]
        let migrated = PenLegacyMigrator.migrate(tree, rules: [PenIconMigrationRule()])
        guard case let .array(children)? = migrated["children"],
              case let .dictionary(root)? = children.first,
              case let .array(rootChildren)? = root["children"],
              case let .dictionary(icon)? = rootChildren.first
        else {
            Issue.record("Expected a migrated nested icon node")
            return
        }
        #expect(icon["type"] == .string("icon"))
        #expect(icon["icon"] == .string("bell"))
        #expect(icon["library"] == .string("lucide"))
    }

    @Test("Rewrites an icon_font descendant override inside a ref")
    func rewritesRefDescendant() {
        let tree: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([
                .dictionary([
                    "id": .string("ref1"),
                    "type": .string("ref"),
                    "ref": .string("component1"),
                    "descendants": .dictionary([
                        "icon1": .dictionary(iconNode()),
                    ]),
                ]),
            ]),
        ]
        let migrated = PenLegacyMigrator.migrate(tree, rules: [PenIconMigrationRule()])
        guard case let .array(children)? = migrated["children"],
              case let .dictionary(ref)? = children.first,
              case let .dictionary(descendants)? = ref["descendants"],
              case let .dictionary(icon)? = descendants["icon1"]
        else {
            Issue.record("Expected a migrated descendant override")
            return
        }
        #expect(icon["type"] == .string("icon"))
        #expect(icon["icon"] == .string("bell"))
        #expect(icon["library"] == .string("lucide"))
    }

    // MARK: - Registration

    @Test("Registered on the default rule set")
    func registeredOnDefaultRules() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenIconMigrationRule })
    }

    // MARK: - Override bags

    @Test("Renames the keys in a property override that carries no type")
    func renamesKeysInTypelessDescendantOverride() {
        let tree: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([
                .dictionary([
                    "id": .string("ref1"),
                    "type": .string("ref"),
                    "ref": .string("component1"),
                    "descendants": .dictionary([
                        "icon1": .dictionary(["iconFontName": .string("heart")]),
                    ]),
                ]),
            ]),
        ]
        let migrated = PenLegacyMigrator.migrate(tree, rules: [PenIconMigrationRule()])
        guard case let .array(children)? = migrated["children"],
              case let .dictionary(ref)? = children.first,
              case let .dictionary(descendants)? = ref["descendants"],
              case let .dictionary(override)? = descendants["icon1"]
        else {
            Issue.record("Expected a migrated descendant override")
            return
        }
        #expect(override["icon"] == .string("heart"))
        #expect(override["iconFontName"] == nil)
        #expect(override["type"] == nil, "A property override must not gain a type")
    }

    @Test("Renames the keys of a ref's own root overrides")
    func renamesKeysInRefRootOverride() {
        var node: [String: AnyCodable] = [
            "id": .string("ref1"),
            "type": .string("ref"),
            "ref": .string("component1"),
            "iconFontFamily": .string("phosphor"),
        ]
        PenIconMigrationRule().apply(toNode: &node, id: "ref1", diagnostics: nil)
        #expect(node["library"] == .string("phosphor"))
        #expect(node["iconFontFamily"] == nil)
        #expect(node["type"] == .string("ref"))
    }
}
