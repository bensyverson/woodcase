//
//  PenNodeBlendModeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A node's own blend mode is stored in `metadata.woodcase.blendMode`, which Pen keeps,
/// not as the top-level `blendMode` Pen drops on load (leaf TesTbK; Ben's ruling of
/// 2026-10-20). A paint's and a shadow's `blendMode` stay where Pen's format puts them.
struct PenNodeBlendModeTests {
    private func node(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(#"{"version": "2.19", "children": ["# + json + "]}")
        return try #require(document.children.first)
    }

    /// The node's JSON object as the file writes it.
    private func written(_ node: PenNode) throws -> [String: AnyCodable] {
        let document = try PenParser.parse(PenParser.encode(PenDocument(version: "2.19", children: [node])))
        let data = try PenParser.encode(document)
        let object = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        guard case let .array(children)? = object["children"], case let .dictionary(first)? = children.first else {
            Issue.record("no node written")
            return [:]
        }
        return first
    }

    private func woodcaseKeys(_ object: [String: AnyCodable]) -> [String: AnyCodable]? {
        guard case let .dictionary(metadata)? = object["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace]
        else { return nil }
        return keys
    }

    // MARK: - The accessor

    @Test("A node's blend mode is read from metadata.woodcase.blendMode")
    func readsMetadata() throws {
        let rectangle = try node(#"""
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "multiply"}}}
        """#)
        #expect(rectangle.blendMode == .multiply)
    }

    @Test("A node with no blend key has no blend mode")
    func absentIsNil() throws {
        #expect(try node(#"{"type": "frame", "id": "f", "width": 10, "height": 10}"#).blendMode == nil)
    }

    @Test("A mode Woodcase does not know is kept as written")
    func unknownModeKept() throws {
        let group = try node(#"""
        {"type": "group", "id": "g", "metadata": {"type": "woodcase", "woodcase": {"blendMode": "plusDarker"}}}
        """#)
        #expect(group.blendMode == .unknown("plusDarker"))
    }

    @Test("A blend key that is not a string is no blend mode")
    func nonStringIsNil() throws {
        let group = try node(#"""
        {"type": "group", "id": "g", "metadata": {"type": "woodcase", "woodcase": {"blendMode": 3}}}
        """#)
        #expect(group.blendMode == nil)
    }

    @Test("Only the types that took a node blend read one", arguments: [
        #"{"type": "note", "id": "n", "content": "Hi", "metadata": {"type": "woodcase", "woodcase": {"blendMode": "multiply"}}}"#,
        #"{"type": "ref", "id": "i", "ref": "c", "metadata": {"type": "woodcase", "woodcase": {"blendMode": "multiply"}}}"#,
    ])
    func otherTypesHaveNone(json: String) throws {
        #expect(try node(json).blendMode == nil)
    }

    @Test("Setting the blend mode writes the namespaced key and keeps the rest of the metadata")
    func setterWritesMetadata() throws {
        var frame = try node(#"""
        {"type": "frame", "id": "f", "width": 10, "height": 10,
         "metadata": {"type": "component", "woodcase": {"role": "button"}}}
        """#)
        frame.blendMode = .screen
        #expect(frame.common.metadata?[woodcase: .blendMode] == .string("screen"))
        #expect(frame.common.metadata?[woodcase: .role] == .string("button"))
        #expect(frame.common.metadata?.type == "component")
    }

    @Test("Clearing the only blend key leaves no metadata behind")
    func clearingRemovesMetadata() throws {
        var frame = try node(#"""
        {"type": "frame", "id": "f", "width": 10, "height": 10,
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "screen"}}}
        """#)
        frame.blendMode = nil
        #expect(frame.common.metadata == nil)
        #expect(frame.blendMode == nil)
    }

    // MARK: - The file

    @Test("A node blend is written into metadata.woodcase, never as a top-level key")
    func writesMetadataOnly() throws {
        var rectangle = try node(#"{"type": "rectangle", "id": "r", "width": 10, "height": 10}"#)
        rectangle.blendMode = .multiply
        let object = try written(rectangle)
        #expect(object["blendMode"] == nil)
        #expect(woodcaseKeys(object)?["blendMode"] == .string("multiply"))
    }

    @Test("A file's old top-level node blend moves into metadata on read", arguments: [
        "frame", "group", "rectangle", "ellipse", "polygon", "path", "line", "text", "icon",
    ])
    func oldTopLevelMigrates(type: String) throws {
        let migrated = try node(#"{"type": "\#(type)", "id": "n", "blendMode": "multiply"}"#)
        #expect(migrated.blendMode == .multiply)
        #expect(migrated.common.metadata?[woodcase: .blendMode] == .string("multiply"))
        #expect(migrated.extras.isEmpty)
        let object = try written(migrated)
        #expect(object["blendMode"] == nil)
        #expect(woodcaseKeys(object)?["blendMode"] == .string("multiply"))
    }

    @Test("An old top-level blend joins metadata the node already carries")
    func oldTopLevelJoinsMetadata() throws {
        let migrated = try node(#"""
        {"type": "frame", "id": "f", "blendMode": "screen", "metadata": {"type": "component", "woodcase": {"role": "card"}}}
        """#)
        #expect(migrated.blendMode == .screen)
        #expect(migrated.common.metadata?[woodcase: .role] == .string("card"))
        #expect(migrated.common.metadata?.type == "component")
    }

    @Test("An override's top-level blend wins over the blend the component node stores")
    func overrideBlendWins() throws {
        let component = try node(#"""
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "screen"}}}
        """#)
        let patched = try PenNodePatcher.patched(component, with: ["blendMode": .string("multiply")])
        #expect(patched.blendMode == .multiply)
    }

    @Test("A paint's and a shadow's blend stay on the paint and the shadow")
    func paintAndShadowBlendStay() throws {
        let rectangle = try node(#"""
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "fill": {"type": "color", "color": "#FF0000", "blendMode": "multiply"},
         "effect": {"type": "shadow", "blur": 4, "color": "#00000080", "blendMode": "screen"}}
        """#)
        #expect(rectangle.blendMode == nil)
        #expect(rectangle.common.metadata == nil)
        let object = try written(rectangle)
        guard case let .dictionary(fill)? = object["fill"], case let .dictionary(effect)? = object["effect"] else {
            Issue.record("fill and effect written as objects: \(object)")
            return
        }
        #expect(fill["blendMode"] == .string("multiply"))
        #expect(effect["blendMode"] == .string("screen"))
    }
}
