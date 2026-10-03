//
//  PenImageModeMigrationRuleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers the 2.19 → 2.20 image-mode upgrade at the raw JSON level, the way Pen 1.2.15
/// rewrites a 2.19 file it opens: `fill` → `cover`, `fit` → `contain`, `stretch` stays,
/// and a missing mode — stretch in 2.19, cover in 2.20 — becomes an explicit `stretch`.
struct PenImageModeMigrationRuleTests {
    // MARK: - Helpers

    private let rule = PenImageModeMigrationRule()

    private func image(_ mode: String?) -> AnyCodable {
        var paint: [String: AnyCodable] = ["type": "image", "url": "./a.png"]
        if let mode {
            paint["mode"] = .string(mode)
        }
        return .dictionary(paint)
    }

    /// Applies the rule to one node and returns the node.
    private func migrated(_ node: [String: AnyCodable]) -> [String: AnyCodable] {
        var result = node
        rule.apply(toNode: &result, id: "N", diagnostics: nil)
        return result
    }

    /// Decodes a JSON object literal as a raw tree.
    private func tree(_ json: String) throws -> [String: AnyCodable] {
        try JSONDecoder().decode([String: AnyCodable].self, from: Data(json.utf8))
    }

    // MARK: - Modes

    @Test("Each 2.19 mode becomes its 2.20 spelling in a node's fill", arguments: [
        ("fill", "cover"), ("fit", "contain"), ("stretch", "stretch"),
    ])
    func modeIsRenamed(old: String, new: String) {
        let node = migrated(["type": "rectangle", "fill": image(old)])
        #expect(node["fill"] == image(new))
    }

    @Test("A missing mode becomes an explicit stretch")
    func missingModeBecomesStretch() {
        let node = migrated(["type": "rectangle", "fill": image(nil)])
        #expect(node["fill"] == image("stretch"))
    }

    @Test("An unknown mode is left untouched")
    func unknownModeIsKept() {
        let node = migrated(["type": "rectangle", "fill": image("tile")])
        #expect(node["fill"] == image("tile"))
    }

    @Test("A paint that is not an image is left untouched")
    func otherPaintsAreKept() {
        let gradient: AnyCodable = ["type": "gradient", "gradientType": "linear"]
        let node = migrated(["type": "rectangle", "fill": gradient, "stroke": "#FF0000"])
        #expect(node["fill"] == gradient)
        #expect(node["stroke"] == "#FF0000")
    }

    // MARK: - Where image paints live

    @Test("Every image in a fill array is upgraded, and a color beside them is kept")
    func fillArray() {
        let node = migrated(["type": "rectangle", "fill": .array(["#FF0000", image("fit"), image(nil)])])
        #expect(node["fill"] == .array(["#FF0000", image("contain"), image("stretch")]))
    }

    @Test("A stroke paint is upgraded, single or in an array")
    func strokePaints() {
        let single = migrated(["type": "rectangle", "stroke": image("fill")])
        #expect(single["stroke"] == image("cover"))
        let array = migrated(["type": "rectangle", "stroke": .array([image("fit"), image(nil)])])
        #expect(array["stroke"] == .array([image("contain"), image("stretch")]))
    }

    @Test("A text node's fill is upgraded")
    func textFill() {
        let node = migrated(["type": "text", "content": "Hi", "fill": image(nil)])
        #expect(node["fill"] == image("stretch"))
    }

    @Test("Through the migrator: nested children, descendant overrides and their replacement children")
    func throughTheMigrator() throws {
        let document = try tree(#"""
        {"version": "2.19", "children": [
          {"id": "C", "type": "frame", "reusable": true, "children": [
            {"id": "K", "type": "rectangle", "fill": {"type": "image", "url": "./a.png", "mode": "fill"}},
            {"id": "S", "type": "frame", "children": [{"id": "D", "type": "rectangle"}]}]},
          {"id": "I", "type": "ref", "ref": "C",
           "fill": {"type": "image", "url": "./a.png", "mode": "fit"},
           "descendants": {
             "K": {"fill": {"type": "image", "url": "./a.png"}, "stroke": {"type": "image", "url": "./a.png", "mode": "fill"}},
             "S": {"type": "frame", "id": "S2", "children": [
               {"id": "R", "type": "rectangle", "fill": [{"type": "image", "url": "./a.png", "mode": "fit"}]}]}}}]}
        """#)
        let result = PenLegacyMigrator.migrate(document, rules: [rule])
        let expected = try tree(#"""
        {"version": "2.19", "children": [
          {"id": "C", "type": "frame", "reusable": true, "children": [
            {"id": "K", "type": "rectangle", "fill": {"type": "image", "url": "./a.png", "mode": "cover"}},
            {"id": "S", "type": "frame", "children": [{"id": "D", "type": "rectangle"}]}]},
          {"id": "I", "type": "ref", "ref": "C",
           "fill": {"type": "image", "url": "./a.png", "mode": "contain"},
           "descendants": {
             "K": {"fill": {"type": "image", "url": "./a.png", "mode": "stretch"}, "stroke": {"type": "image", "url": "./a.png", "mode": "cover"}},
             "S": {"type": "frame", "id": "S2", "children": [
               {"id": "R", "type": "rectangle", "fill": [{"type": "image", "url": "./a.png", "mode": "contain"}]}]}}}]}
        """#)
        #expect(result == expected)
    }

    @Test("A legacy stroke's own image fill is flattened first, then upgraded as a stroke paint")
    func legacyNestedStrokeFill() throws {
        let document = try tree(#"""
        {"version": "2.9", "children": [{"id": "R", "type": "rectangle",
          "stroke": {"thickness": 2, "fill": {"type": "image", "url": "./a.png", "mode": "fit"}}}]}
        """#)
        let result = PenLegacyMigrator.migrate(document)
        guard case let .array(children)? = result["children"], case let .dictionary(node)? = children.first else {
            Issue.record("no migrated node in \(result)")
            return
        }
        #expect(node["stroke"] == image("contain"))
    }

    // MARK: - Contract

    @Test("The rule says nothing: every rewrite keeps the file looking the same")
    func isSilent() {
        let diagnostics = PenDiagnosticCollector()
        var node: [String: AnyCodable] = ["type": "rectangle", "fill": .array([image("fill"), image(nil)])]
        rule.apply(toNode: &node, id: "N", diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test("The rule upgrades a document to 2.20")
    func targetIs220() {
        #expect(rule.target == PenFormatVersion(major: 2, minor: 20))
    }

    @Test("The byte hint says no only for bytes without an image in them")
    func byteHint() {
        #expect(!rule.mayApply(to: Data(##"{"children":[{"type":"rectangle","fill":"#FFF"}]}"##.utf8)))
        #expect(rule.mayApply(to: Data(#"{"children":[{"fill":{"type":"image"}}]}"#.utf8)))
    }
}
