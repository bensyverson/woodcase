//
//  PenGroupMigrationRuleTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

struct PenGroupMigrationRuleTests {
    private func node(_ properties: [String: AnyCodable]) -> [String: AnyCodable] {
        var node = properties
        node["type"] = .string("group")
        return node
    }

    // MARK: - Non-group nodes are untouched

    @Test("A non-group node is untouched")
    func nonGroupNodeUntouched() {
        var node: [String: AnyCodable] = ["type": .string("frame"), "layout": .string("vertical")]
        PenGroupMigrationRule().apply(toNode: &node, id: "f1", diagnostics: nil)
        #expect(node["layout"] == .string("vertical"))
    }

    // MARK: - Keys are removed

    @Test("Removes layout, gap, padding, justifyContent, alignItems, width, height from a group")
    func removesAllLegacyKeys() {
        var node = node([
            "layout": .string("horizontal"),
            "gap": .int(8),
            "padding": .int(4),
            "justifyContent": .string("center"),
            "alignItems": .string("center"),
            "width": .int(200),
            "height": .int(100),
        ])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: nil)
        #expect(node["layout"] == nil)
        #expect(node["gap"] == nil)
        #expect(node["padding"] == nil)
        #expect(node["justifyContent"] == nil)
        #expect(node["alignItems"] == nil)
        #expect(node["width"] == nil)
        #expect(node["height"] == nil)
    }

    @Test("A group node with none of the legacy keys is untouched")
    func groupWithoutLegacyKeysUntouched() {
        var node = node(["children": .array([])])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: nil)
        #expect(node == ["type": .string("group"), "children": .array([])])
    }

    // MARK: - Silent defaults

    @Test("layout: none is dropped silently")
    func layoutNoneIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["layout": .string("none")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(node["layout"] == nil)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("gap: 0 is dropped silently")
    func gapZeroIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["gap": .int(0)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("padding: 0 is dropped silently")
    func paddingZeroIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["padding": .double(0)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("A zero 4-element padding array is dropped silently")
    func paddingZeroArrayIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["padding": .array([.int(0), .int(0), .int(0), .int(0)])])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("justifyContent: start is dropped silently")
    func justifyStartIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["justifyContent": .string("start")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("alignItems: start is dropped silently")
    func alignStartIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["alignItems": .string("start")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("width/height: fit_content is dropped silently")
    func fitContentIsSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["width": .string("fit_content"), "height": .string("fit_content")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    // MARK: - Non-default values emit a diagnostic

    @Test("A non-default layout emits a diagnostic naming the key")
    func nonDefaultLayoutEmitsDiagnostic() throws {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["layout": .string("horizontal")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.nodeID == "g1")
        #expect(diagnostic.message.contains("layout"))
    }

    @Test("A nonzero gap emits a diagnostic")
    func nonzeroGapEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["gap": .int(8)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("gap") == true)
    }

    @Test("A nonzero padding emits a diagnostic")
    func nonzeroPaddingEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["padding": .array([.int(4), .int(0), .int(0), .int(0)])])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("padding") == true)
    }

    @Test("A non-start justifyContent emits a diagnostic")
    func nonDefaultJustifyEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["justifyContent": .string("center")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("justifyContent") == true)
    }

    @Test("A non-start alignItems emits a diagnostic")
    func nonDefaultAlignEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["alignItems": .string("center")])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("alignItems") == true)
    }

    @Test("An explicit width emits a diagnostic")
    func explicitWidthEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["width": .int(200)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("width") == true)
    }

    @Test("An explicit height emits a diagnostic")
    func explicitHeightEmitsDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["height": .int(100)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.first?.message.contains("height") == true)
    }

    @Test("Multiple non-default keys are listed in one diagnostic")
    func multipleNonDefaultKeysOneDiagnostic() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["layout": .string("horizontal"), "gap": .int(8)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.count == 1)
        let message = diagnostics.diagnostics.first?.message ?? ""
        #expect(message.contains("layout"))
        #expect(message.contains("gap"))
    }

    @Test("A mix of default and non-default keys reports only the non-default ones")
    func mixOfDefaultAndNonDefaultReportsOnlyNonDefault() {
        let diagnostics = PenDiagnosticCollector()
        var node = node(["layout": .string("none"), "gap": .int(8)])
        PenGroupMigrationRule().apply(toNode: &node, id: "g1", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.count == 1)
        let message = diagnostics.diagnostics.first?.message ?? ""
        // The default `layout: "none"` must not appear in the listed keys (the word
        // "layout" does appear in the message's own prose, so check for the key
        // itself — comma- or colon-preceded — rather than the bare substring).
        #expect(!message.contains(": layout"))
        #expect(!message.contains(", layout"))
        #expect(message.contains("gap"))
    }

    // MARK: - Reaches nested and descendant nodes

    @Test("A nested group inside a frame's children is migrated")
    func nestedGroupIsMigrated() {
        let diagnostics = PenDiagnosticCollector()
        let tree: [String: AnyCodable] = [
            "version": .string("2.9"),
            "children": .array([
                .dictionary([
                    "id": .string("frame1"),
                    "type": .string("frame"),
                    "children": .array([
                        .dictionary([
                            "id": .string("group1"),
                            "type": .string("group"),
                            "layout": .string("vertical"),
                        ]),
                    ]),
                ]),
            ]),
        ]
        let migrated = PenLegacyMigrator.migrate(tree, rules: [PenGroupMigrationRule()], diagnostics: diagnostics)
        guard case let .array(children)? = migrated["children"],
              case let .dictionary(frame)? = children.first,
              case let .array(frameChildren)? = frame["children"],
              case let .dictionary(group)? = frameChildren.first
        else {
            Issue.record("Expected the nested group to survive migration")
            return
        }
        #expect(group["layout"] == nil)
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "group1" })
    }

    // MARK: - Registration

    @Test("The rule is registered on the default migrator")
    func ruleIsRegistered() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenGroupMigrationRule })
    }
}
