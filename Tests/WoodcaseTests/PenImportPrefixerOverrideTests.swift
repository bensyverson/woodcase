//
//  PenImportPrefixerOverrideTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("PenImportPrefixer Descendant Override Values")
struct PenImportPrefixerOverrideTests {
    /// Creates a minimal library component (ref node) with the given descendant overrides,
    /// prefixes it, and returns the prefixed override values.
    private func prefixOverrides(
        _ overrides: [String: PenDescendantOverride],
        alias: String = "V"
    ) -> [String: PenDescendantOverride]? {
        let refNode = PenNode(
            id: "testRef",
            common: PenNodeCommon(reusable: true),
            kind: .ref(PenNode.RefData(
                ref: "target",
                descendants: overrides
            ))
        )
        let prefixed = PenImportPrefixer.prefixNode(refNode, alias: alias)
        guard case let .ref(data) = prefixed.kind else { return nil }
        return data.descendants
    }

    // MARK: - Ref targets in override children

    @Test("Prefixes ref targets in override children")
    func prefixesRefTargetsInChildren() throws {
        let override = PenDescendantOverride(properties: [
            "children": .array([
                .dictionary([
                    "id": .string("NtF0f"),
                    "type": .string("ref"),
                    "ref": .string("VSnC2"),
                ]),
            ]),
        ])

        let result = try #require(prefixOverrides(["node1": override]))
        let prefixedOverride = try #require(result["V:node1"])
        guard case let .array(children) = prefixedOverride.properties["children"],
              case let .dictionary(child) = children[0],
              case let .string(refTarget) = child["ref"],
              case let .string(childID) = child["id"]
        else {
            Issue.record("Expected children array with ref dict")
            return
        }

        #expect(refTarget == "V:VSnC2")
        #expect(childID == "V:NtF0f")
    }

    @Test("Prefixes nested descendant keys in override children")
    func prefixesNestedDescendantKeys() throws {
        let override = PenDescendantOverride(properties: [
            "children": .array([
                .dictionary([
                    "id": .string("refNode"),
                    "type": .string("ref"),
                    "ref": .string("target"),
                    "descendants": .dictionary([
                        "innerNode": .dictionary([
                            "content": .string("Hello"),
                        ]),
                    ]),
                ]),
            ]),
        ])

        let result = try #require(prefixOverrides(["node1": override]))
        let prefixedOverride = try #require(result["V:node1"])
        guard case let .array(children) = prefixedOverride.properties["children"],
              case let .dictionary(child) = children[0],
              case let .dictionary(descendants) = child["descendants"]
        else {
            Issue.record("Expected descendants dict in child")
            return
        }

        #expect(descendants["V:innerNode"] != nil)
        #expect(descendants["innerNode"] == nil)
    }

    @Test("Prefixes variable references in override children")
    func prefixesVariableRefsInChildren() throws {
        let override = PenDescendantOverride(properties: [
            "children": .array([
                .dictionary([
                    "id": .string("textNode"),
                    "type": .string("text"),
                    "fill": .string("$--primary"),
                ]),
            ]),
        ])

        let result = try #require(prefixOverrides(["node1": override]))
        let prefixedOverride = try #require(result["V:node1"])
        guard case let .array(children) = prefixedOverride.properties["children"],
              case let .dictionary(child) = children[0],
              case let .string(fill) = child["fill"]
        else {
            Issue.record("Expected fill in child")
            return
        }

        #expect(fill == "$V:--primary")
    }

    // MARK: - Direct ref target in override

    @Test("Prefixes ref target set directly in override properties")
    func prefixesDirectRefTarget() throws {
        let override = PenDescendantOverride(properties: [
            "ref": .string("someComponent"),
            "type": .string("ref"),
        ])

        let result = try #require(prefixOverrides(["node1": override]))
        let prefixedOverride = try #require(result["V:node1"])
        guard case let .string(refTarget) = prefixedOverride.properties["ref"] else {
            Issue.record("Expected ref string")
            return
        }

        #expect(refTarget == "V:someComponent")
    }

    // MARK: - Banking app regression

    @Test("Banking app: no unresolved refs after expansion")
    func bankingNoUnresolvedRefs() throws {
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let bankingURL = fixturesDir.appendingPathComponent("banking.pen")
        let kitURL = fixturesDir.appendingPathComponent("kit.lib.pen")

        let banking = try PenParser.parse(contentsOf: bankingURL)
        let kit = try PenParser.parse(contentsOf: kitURL)

        let imported = PenImportResolver.resolve(
            banking, libraries: ["kit.lib.pen": kit]
        )
        let expanded = PenRefExpander.expand(imported)
        let resolved = PenVariableResolver.resolve(expanded, theme: ["scheme": "day", "V:scheme": "day"])

        let unresolvedRefs = countRefs(in: resolved.children)
        for ref in unresolvedRefs {
            print("  Unresolved ref: \(ref.id) → \(ref.ref)")
        }
        #expect(unresolvedRefs.isEmpty, "Found \(unresolvedRefs.count) unresolved refs")
    }

    private func countRefs(in nodes: [PenNode]) -> [(id: String, ref: String)] {
        var refs: [(id: String, ref: String)] = []
        for node in nodes {
            if case let .ref(data) = node.kind {
                refs.append((id: node.id, ref: data.ref))
            }
            switch node.kind {
            case let .frame(data):
                if let children = data.children { refs.append(contentsOf: countRefs(in: children)) }
            case let .group(data):
                if let children = data.children { refs.append(contentsOf: countRefs(in: children)) }
            default: break
            }
        }
        return refs
    }
}
