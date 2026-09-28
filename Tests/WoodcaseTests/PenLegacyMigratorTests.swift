//
//  PenLegacyMigratorTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

struct PenLegacyMigratorTests {
    // MARK: - Test Rules

    /// Marks every node it visits and reports the node id, so the walker can be observed.
    private struct TagRule: PenMigrationRule {
        func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
            node["tagged"] = .bool(true)
            diagnostics?.warn("visited", stage: .migration, nodeID: id)
        }
    }

    /// Only implements the document-level hook, proving the node hook has a default.
    private struct StampRule: PenMigrationRule {
        func apply(toDocument document: inout [String: AnyCodable], diagnostics _: PenDiagnosticCollector?) {
            document["stamped"] = .bool(true)
        }
    }

    /// Implements neither hook, proving both defaults are no-ops.
    private struct InertRule: PenMigrationRule {}

    // MARK: - Fixture Trees

    /// A legacy tree with nested children and a `ref` carrying descendant overrides.
    private var legacyTree: [String: AnyCodable] {
        [
            "version": .string("2.9"),
            "children": .array([
                .dictionary([
                    "id": .string("frame1"),
                    "type": .string("frame"),
                    "children": .array([
                        .dictionary([
                            "id": .string("group1"),
                            "type": .string("group"),
                            "children": .array([
                                .dictionary(["id": .string("rect1"), "type": .string("rectangle")]),
                            ]),
                        ]),
                    ]),
                ]),
                .dictionary([
                    "id": .string("ref1"),
                    "type": .string("ref"),
                    "ref": .string("frame1"),
                    "descendants": .dictionary([
                        "group1/rect1": .dictionary(["fill": .string("#FF0000")]),
                        "group1": .dictionary([
                            "type": .string("group"),
                            "children": .array([
                                .dictionary(["id": .string("nested"), "type": .string("text")]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]
    }

    /// Collects every `tagged` marker found in the tree, keyed by the node id where one exists.
    private func taggedNodeIDs(in value: AnyCodable) -> Set<String> {
        var found: Set<String> = []
        switch value {
        case let .dictionary(dict):
            if dict["tagged"] == .bool(true) {
                if case let .string(id)? = dict["id"] {
                    found.insert(id)
                } else {
                    found.insert("<anonymous>")
                }
            }
            for nested in dict.values {
                found.formUnion(taggedNodeIDs(in: nested))
            }
        case let .array(items):
            for item in items {
                found.formUnion(taggedNodeIDs(in: item))
            }
        default:
            break
        }
        return found
    }

    // MARK: - Walking

    @Test("A rule reaches every node, including nested children and ref descendants")
    func rulesReachEveryNode() {
        let migrated = PenLegacyMigrator.migrate(legacyTree, rules: [TagRule()])
        let tagged = taggedNodeIDs(in: .dictionary(migrated))
        #expect(tagged.isSuperset(of: ["frame1", "group1", "rect1", "ref1", "nested"]))
        // The two descendant overrides carry no id of their own.
        #expect(tagged.contains("<anonymous>"))
    }

    @Test("The document root is not treated as a node")
    func rootIsNotANode() {
        let migrated = PenLegacyMigrator.migrate(legacyTree, rules: [TagRule()])
        #expect(migrated["tagged"] == nil)
    }

    @Test("Node diagnostics carry the node id")
    func diagnosticsCarryNodeID() {
        let diagnostics = PenDiagnosticCollector()
        _ = PenLegacyMigrator.migrate(legacyTree, rules: [TagRule()], diagnostics: diagnostics)
        let ids = Set(diagnostics.diagnostics.compactMap(\.nodeID))
        #expect(ids.isSuperset(of: ["frame1", "group1", "rect1", "ref1", "nested"]))
        #expect(diagnostics.diagnostics.allSatisfy { $0.stage == .migration })
    }

    @Test("A descendant override without an id reports its override path")
    func descendantOverrideReportsPath() {
        let diagnostics = PenDiagnosticCollector()
        _ = PenLegacyMigrator.migrate(legacyTree, rules: [TagRule()], diagnostics: diagnostics)
        let ids = Set(diagnostics.diagnostics.compactMap(\.nodeID))
        #expect(ids.contains("group1/rect1"))
    }

    // MARK: - Hooks

    @Test("The document hook rewrites root keys")
    func documentHookApplies() {
        let migrated = PenLegacyMigrator.migrate(legacyTree, rules: [StampRule()])
        #expect(migrated["stamped"] == .bool(true))
    }

    @Test("A rule implementing neither hook leaves the tree untouched")
    func inertRuleIsANoOp() {
        let migrated = PenLegacyMigrator.migrate(legacyTree, rules: [InertRule()])
        #expect(migrated == legacyTree)
    }

    // MARK: - The shipped rule set

    @Test("The default rule set rewrites the version to the model's")
    func defaultRulesRewriteVersion() {
        let migrated = PenLegacyMigrator.migrate(legacyTree)
        #expect(migrated["version"] == .string(PenDocument.currentFormatVersion))
    }

    @Test("The version rule stamps the current version on its own")
    func versionRuleStampsVersion() {
        var document: [String: AnyCodable] = ["version": .string("2.9")]
        PenVersionMigrationRule().apply(toDocument: &document, diagnostics: nil)
        #expect(document["version"] == .string(PenDocument.currentFormatVersion))
    }

    @Test("Migrating a tree already at the model's version is a no-op")
    func noOpOnCurrentTree() {
        var current = legacyTree
        current["version"] = .string(PenDocument.currentFormatVersion)
        let migrated = PenLegacyMigrator.migrate(current)
        #expect(migrated == current)
    }

    @Test("A document's declared version picks the rules it needs", arguments: [
        (nil, "legacy"), ("2.9", "legacy"), ("2.10", "legacy"),
        ("2.11", "modern"), ("2.17", "modern"), ("2.18", "modern"),
        ("2.19", "none"), ("2.20", "none"),
    ] as [(String?, String)])
    func rulesForVersion(declared: String?, expected: String) {
        let rules = PenLegacyMigrator.rules(upgrading: declared.flatMap(PenFormatVersion.init))
        let kind = if rules.isEmpty {
            "none"
        } else if rules.count == PenLegacyMigrator.rules.count {
            "legacy"
        } else if rules.count == PenLegacyMigrator.modernRules.count {
            "modern"
        } else {
            "other"
        }
        #expect(kind == expected)
    }

    @Test("Both rule sets end in the 2.19 shadow migration")
    func shadowRuleIsRegistered() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenShadowMigrationRule })
        #expect(PenLegacyMigrator.modernRules.contains { $0 is PenShadowMigrationRule })
    }

    @Test("The default rule set is non-empty and registered on the migrator")
    func defaultRuleSetIsRegistered() {
        #expect(!PenLegacyMigrator.rules.isEmpty)
    }
}
