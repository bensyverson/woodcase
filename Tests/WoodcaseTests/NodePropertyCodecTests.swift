//
//  NodePropertyCodecTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct NodePropertyCodecTests {
    // MARK: - Helpers

    private func rect() -> PenNode {
        PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect", x: .literal(10), opacity: .literal(1.0)),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(100),
                height: .fixed(50),
                fills: .single(.shorthand("red"))
            ))
        )
    }

    // MARK: - Vocabulary

    @Test("paths(for:) lists every common path and the node's own kind paths")
    func pathsListsVocabulary() {
        let paths = Set(NodePropertyCodec.paths(for: rect()))

        #expect(paths.contains("common.name"))
        #expect(paths.contains("common.x"))
        #expect(paths.contains("common.metadata"))
        #expect(paths.contains("kind.width"))
        #expect(paths.contains("kind.fills"))
        #expect(paths.contains("kind.cornerRadius"))
        // A text-only property is not part of a rectangle's vocabulary.
        #expect(!paths.contains("kind.fontSize"))
        // `kind.type` is PropertyDiff's marker for a whole-kind swap, not a patchable path.
        #expect(!paths.contains("kind.type"))
    }

    @Test("paths(for:) is sorted so the listing is stable")
    func pathsAreSorted() {
        let paths = NodePropertyCodec.paths(for: rect())
        #expect(paths == paths.sorted())
    }

    @Test("paths(for:) matches PropertyDiff's kind vocabulary exactly")
    func pathsMatchPropertyDiff() {
        let node = rect()
        let kindPaths = Set(NodePropertyCodec.paths(for: node).filter { $0.hasPrefix("kind.") })
        #expect(kindPaths == PropertyDiff.allKindKeys(node.kind))
    }

    @Test("The common vocabulary is exactly what PropertyDiff can emit")
    func commonVocabularyMatchesPropertyDiff() {
        let changed = PenNodeCommon(
            name: "n",
            x: .literal(1), y: .literal(2), rotation: .literal(3), opacity: .literal(0.5),
            enabled: .literal(false), flipX: .literal(true), flipY: .literal(true),
            reusable: true,
            theme: ["mode": "dark"],
            context: "ctx",
            layoutPosition: .absolute,
            metadata: PenMetadata(type: "component")
        )
        #expect(PropertyDiff.diffCommon(old: PenNodeCommon(), new: changed) == NodePropertyCodec.commonPaths)
    }

    // MARK: - Reading

    @Test("value(at:of:) reads a kind property in .pen wire shape")
    func readsKindValue() throws {
        let value = try NodePropertyCodec.value(at: "kind.width", of: rect())
        #expect(value == .int(100))
    }

    @Test("value(at:of:) reads a common property in .pen wire shape")
    func readsCommonValue() throws {
        let value = try NodePropertyCodec.value(at: "common.name", of: rect())
        #expect(value == .string("Rect"))
    }

    @Test("value(at:of:) reads an unset property as null")
    func readsUnsetAsNull() throws {
        let value = try NodePropertyCodec.value(at: "kind.cornerRadius", of: rect())
        #expect(value == .null)
    }

    @Test("value(at:of:) throws unknownProperty for a key of another kind")
    func readingUnknownKeyThrows() {
        #expect(throws: EditingError.unknownProperty(nodeID: "r1", key: "kind.fontSize", nodeType: "rectangle")) {
            _ = try NodePropertyCodec.value(at: "kind.fontSize", of: rect())
        }
    }

    // MARK: - Writing

    @Test("setting(_:at:on:) writes one kind property and leaves the rest alone")
    func writesOneKindProperty() throws {
        let patched = try NodePropertyCodec.setting(.int(200), at: "kind.width", on: rect())
        guard case let .rectangle(data) = patched.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.width == .fixed(200))
        #expect(data.height == .fixed(50))
        #expect(data.fills == .single(.shorthand("red")))
        #expect(patched.common == rect().common)
    }

    @Test("setting(_:at:on:) writes a common property")
    func writesCommonProperty() throws {
        let patched = try NodePropertyCodec.setting(.string("Renamed"), at: "common.name", on: rect())
        #expect(patched.common.name == "Renamed")
        #expect(patched.common.x == .literal(10))
    }

    @Test("setting a null clears the property")
    func nullClearsProperty() throws {
        let patched = try NodePropertyCodec.setting(.null, at: "kind.fills", on: rect())
        guard case let .rectangle(data) = patched.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.fills == nil)
        #expect(data.width == .fixed(100))
    }

    @Test("setting(_:at:on:) throws unknownProperty for a key of another kind")
    func writingUnknownKeyThrows() {
        #expect(throws: EditingError.unknownProperty(nodeID: "r1", key: "kind.fontSize", nodeType: "rectangle")) {
            _ = try NodePropertyCodec.setting(.int(12), at: "kind.fontSize", on: rect())
        }
    }

    @Test("setting(_:at:on:) throws unknownProperty for a typo'd common key")
    func writingTypoThrows() {
        #expect(throws: EditingError.unknownProperty(nodeID: "r1", key: "common.opactiy", nodeType: "rectangle")) {
            _ = try NodePropertyCodec.setting(.double(0.5), at: "common.opactiy", on: rect())
        }
    }

    @Test("setting(_:at:on:) throws unknownProperty for a path with no prefix")
    func writingUnprefixedKeyThrows() {
        #expect(throws: EditingError.unknownProperty(nodeID: "r1", key: "width", nodeType: "rectangle")) {
            _ = try NodePropertyCodec.setting(.int(10), at: "width", on: rect())
        }
    }

    @Test("setting a wrong-typed value throws propertyTypeMismatch with human descriptions")
    func typeMismatchThrows() {
        #expect(throws: EditingError.propertyTypeMismatch(
            nodeID: "r1", key: "common.opacity", expected: "a number or a $variable", actual: "a boolean"
        )) {
            _ = try NodePropertyCodec.setting(.bool(true), at: "common.opacity", on: rect())
        }
    }

    @Test("setting a wrong-typed sizing value names the sizing vocabulary")
    func sizingMismatchThrows() {
        #expect(throws: EditingError.propertyTypeMismatch(
            nodeID: "r1",
            key: "kind.width",
            expected: "a number, \"fit_content\", \"fill_container\", or a $variable",
            actual: "a string"
        )) {
            _ = try NodePropertyCodec.setting(.string("wide"), at: "kind.width", on: rect())
        }
    }

    @Test("clearing a required property reports a type mismatch, not a silent nil")
    func clearingRequiredPropertyThrows() {
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "Button"))
        )
        #expect(throws: EditingError.propertyTypeMismatch(
            nodeID: "ref1", key: "kind.ref", expected: "a string", actual: "null"
        )) {
            _ = try NodePropertyCodec.setting(.null, at: "kind.ref", on: refNode)
        }
    }

    // MARK: - Variable references

    @Test("A $variable round-trips through a PenValue property")
    func variableRoundTripsThroughPenValue() throws {
        let patched = try NodePropertyCodec.setting(.string("$spacing.lg"), at: "common.x", on: rect())
        #expect(patched.common.x == .variable("spacing.lg"))
        #expect(try NodePropertyCodec.value(at: "common.x", of: patched) == .string("$spacing.lg"))
    }

    @Test("A $variable round-trips through a PenSizing property")
    func variableRoundTripsThroughSizing() throws {
        let patched = try NodePropertyCodec.setting(.string("$size.card"), at: "kind.width", on: rect())
        guard case let .rectangle(data) = patched.kind else {
            Issue.record("Expected rectangle")
            return
        }
        #expect(data.width == .variable("size.card"))
        #expect(try NodePropertyCodec.value(at: "kind.width", of: patched) == .string("$size.card"))
    }

    // MARK: - Ref nodes (custom Codable — rootOverrides is flattened on the wire)

    @Test("A ref node's three paths read and write without disturbing each other")
    func refPathsRoundTrip() throws {
        let refNode = PenNode(
            id: "ref1",
            common: PenNodeCommon(),
            kind: .ref(PenNode.RefData(ref: "Button", rootOverrides: ["width": .int(80)]))
        )
        #expect(Set(NodePropertyCodec.paths(for: refNode).filter { $0.hasPrefix("kind.") })
            == ["kind.ref", "kind.descendants", "kind.rootOverrides"])

        #expect(try NodePropertyCodec.value(at: "kind.rootOverrides", of: refNode)
            == .dictionary(["width": .int(80)]))

        let patched = try NodePropertyCodec.setting(.string("Card"), at: "kind.ref", on: refNode)
        guard case let .ref(data) = patched.kind else {
            Issue.record("Expected ref")
            return
        }
        #expect(data.ref == "Card")
        #expect(data.rootOverrides == ["width": .int(80)])
    }

    // MARK: - Unknown kinds

    private func unknownNode() -> PenNode {
        PenNode(
            id: "u1",
            common: PenNodeCommon(),
            kind: .unknown(typeName: "sparkle", properties: ["glow": .int(3)])
        )
    }

    @Test("An unknown kind lists the keys it already carries")
    func unknownKindVocabulary() throws {
        let paths = Set(NodePropertyCodec.paths(for: unknownNode()).filter { $0.hasPrefix("kind.") })
        #expect(paths == ["kind.glow"])
        #expect(try NodePropertyCodec.value(at: "kind.glow", of: unknownNode()) == .int(3))
    }

    @Test("An unknown kind accepts a key it has never seen — there is no schema to check")
    func unknownKindAcceptsNewKeys() throws {
        let patched = try NodePropertyCodec.setting(.int(1), at: "kind.shimmer", on: unknownNode())
        guard case let .unknown(typeName, properties) = patched.kind else {
            Issue.record("Expected unknown kind")
            return
        }
        #expect(typeName == "sparkle")
        #expect(properties == ["glow": .int(3), "shimmer": .int(1)])
    }

    @Test("An unknown kind still rejects a path with no kind prefix")
    func unknownKindRejectsUnprefixedKey() {
        #expect(throws: EditingError.unknownProperty(nodeID: "u1", key: "shimmer", nodeType: "sparkle")) {
            _ = try NodePropertyCodec.setting(.int(1), at: "shimmer", on: self.unknownNode())
        }
    }

    @Test("Reading an absent key on an unknown kind is null, not an error")
    func unknownKindAbsentKeyReadsNull() throws {
        #expect(try NodePropertyCodec.value(at: "kind.shimmer", of: unknownNode()) == .null)
    }

    // MARK: - Every kind's whole vocabulary survives a read/write round trip

    @Test("Every path of every kind reads back as what was written", arguments: NodePropertyCodecTests.allKinds())
    func everyPathRoundTrips(kind: PenNode.Kind) throws {
        let node = PenNode(id: "n1", common: PenNodeCommon(), kind: kind)
        for path in NodePropertyCodec.paths(for: node) {
            let original = try NodePropertyCodec.value(at: path, of: node)
            let patched = try NodePropertyCodec.setting(original, at: path, on: node)
            let readBack = try NodePropertyCodec.value(at: path, of: patched)
            #expect(readBack == original, "\(path) did not round-trip")
        }
    }

    nonisolated static func allKinds() -> [PenNode.Kind] {
        [
            .frame(PenNode.FrameData(width: .fixed(10), fills: .single(.shorthand("red")))),
            .text(PenNode.TextData(content: .literal("hi"), fontSize: .literal(12))),
            .rectangle(PenNode.RectangleData(width: .fixed(10))),
            .ellipse(PenNode.EllipseData(width: .fixed(10))),
            .path(PenNode.PathData(geometry: "M0 0 L1 1")),
            .group(PenNode.GroupData(blendMode: .multiply)),
            .line(PenNode.LineData(width: .fixed(10))),
            .polygon(PenNode.PolygonData(width: .fixed(10))),
            .ref(PenNode.RefData(ref: "Button")),
            .note(PenNode.NoteData(content: .literal("note"))),
            .prompt(PenNode.PromptData(content: .literal("prompt"), model: "m")),
            .context(PenNode.ContextData(content: .literal("ctx"))),
            .icon(PenNode.IconData(icon: .literal("star"))),
            .script(PenNode.ScriptData(scriptUri: "s.js")),
            .browser(PenNode.BrowserData(url: "example.com")),
        ]
    }
}
