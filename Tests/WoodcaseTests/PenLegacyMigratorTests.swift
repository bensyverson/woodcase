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
        let target = PenFormatVersion.current

        func apply(toNode node: inout [String: AnyCodable], id: String?, diagnostics: PenDiagnosticCollector?) {
            node["tagged"] = .bool(true)
            diagnostics?.warn("visited", stage: .migration, nodeID: id)
        }
    }

    /// Only implements the document-level hook, proving the node hook has a default.
    private struct StampRule: PenMigrationRule {
        let target = PenFormatVersion.current

        func apply(toDocument document: inout [String: AnyCodable], diagnostics _: PenDiagnosticCollector?) {
            document["stamped"] = .bool(true)
        }
    }

    /// Implements neither hook, proving both defaults are no-ops.
    private struct InertRule: PenMigrationRule {
        let target = PenFormatVersion.current
    }

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

    /// The type names of the rules a declared version gets, in the order they run.
    private func ruleNames(upgrading declared: String?) -> [String] {
        PenLegacyMigrator.rules(upgrading: declared.flatMap(PenFormatVersion.init)).map { "\(type(of: $0))" }
    }

    /// Whether `first` runs before `second` for a document declaring `declared`.
    private func runs(_ first: String, before second: String, upgrading declared: String?) -> Bool {
        let names = ruleNames(upgrading: declared)
        guard let lhs = names.firstIndex(of: first), let rhs = names.firstIndex(of: second) else { return false }
        return lhs < rhs
    }

    @Test("A legacy document gets every rule, the 2.19 shadow rule before the 2.20 image rule",
          arguments: [nil, "2.9", "2.10"] as [String?])
    func legacyGetsEveryRule(declared: String?) {
        #expect(ruleNames(upgrading: declared).count == PenLegacyMigrator.rules.count)
        #expect(runs("PenShadowMigrationRule", before: "PenImageModeMigrationRule", upgrading: declared))
    }

    @Test("A 2.11 – 2.18 document gets the version stamp, then the shadow rule before the image rule",
          arguments: ["2.11", "2.17", "2.18"])
    func modernGetsShadowThenImage(declared: String) {
        #expect(Set(ruleNames(upgrading: declared)) == [
            "PenVersionMigrationRule", "PenShadowMigrationRule", "PenImageModeMigrationRule",
        ])
        #expect(runs("PenShadowMigrationRule", before: "PenImageModeMigrationRule", upgrading: declared))
    }

    @Test("A 2.19 document never gets the 2.19 shadow rule, only the image rule and the version stamp")
    func format219SkipsTheShadowRule() {
        #expect(Set(ruleNames(upgrading: "2.19")) == ["PenVersionMigrationRule", "PenImageModeMigrationRule"])
    }

    @Test("A document at or past the model's version gets no rules", arguments: ["2.20", "2.21"])
    func currentGetsNothing(declared: String) {
        #expect(ruleNames(upgrading: declared).isEmpty)
    }

    @Test("The rules a document gets run in the order of the versions they upgrade to",
          arguments: [nil, "2.11", "2.19"] as [String?])
    func rulesRunInVersionOrder(declared: String?) {
        let targets = PenLegacyMigrator.rules(upgrading: declared.flatMap(PenFormatVersion.init)).map(\.target)
        #expect(!targets.isEmpty)
        #expect(targets == targets.sorted())
    }

    @Test("The rule set registers the 2.19 shadow rule and the 2.20 image rule")
    func modernRulesAreRegistered() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenShadowMigrationRule })
        #expect(PenLegacyMigrator.rules.contains { $0 is PenImageModeMigrationRule })
    }

    @Test("The default rule set is non-empty and registered on the migrator")
    func defaultRuleSetIsRegistered() {
        #expect(!PenLegacyMigrator.rules.isEmpty)
    }
}
