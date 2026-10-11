//
//  WoodcaseMetadataNamespaceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Everything Woodcase owns in a node's metadata lives under `metadata.woodcase`, and
/// the old spellings — bare post-it keys on a `type: postit` object, underscore
/// code-gen keys — are still read, the namespace winning. See
/// `../Penumbra/project/2026-10-11-notes-comments-and-spans.md`, decision 2.
struct WoodcaseMetadataNamespaceTests {
    private func metadata(_ json: String) throws -> PenMetadata {
        try JSONDecoder().decode(PenMetadata.self, from: Data(json.utf8))
    }

    private func object(_ metadata: PenMetadata) throws -> [String: AnyCodable] {
        try JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
    }

    // MARK: - Reading

    @Test("A namespaced key reads from metadata.woodcase")
    func readsNamespacedKey() throws {
        let read = try metadata(##"{ "woodcase": { "role": "button", "tint": "#A5D6A7" } }"##)

        #expect(read[woodcase: .role] == .string("button"))
        #expect(read[woodcase: .tint] == .string("#A5D6A7"))
        #expect(read[woodcase: .state] == nil)
    }

    @Test("An underscore code-gen key reads as its namespaced key")
    func readsUnderscoreKeys() throws {
        let read = try metadata("""
        { "type": "component", "_props": { "label": "Title" }, "_role": "button",
          "_states": { "hover": "abc" }, "_action": "submit", "_scroll": "vertical" }
        """)

        #expect(read[woodcase: .props] == .dictionary(["label": .string("Title")]))
        #expect(read[woodcase: .role] == .string("button"))
        #expect(read[woodcase: .states] == .dictionary(["hover": .string("abc")]))
        #expect(read[woodcase: .action] == .string("submit"))
        #expect(read[woodcase: .scroll] == .string("vertical"))
    }

    @Test("Bare post-it keys read as namespaced keys on a type: postit object")
    func readsBarePostItKeys() throws {
        let read = try metadata("""
        { "type": "postit", "state": "open", "author": "claude", "tint": "#FFF59D",
          "leaf": "pODcm0", "stage": "Capture", "copiedFrom": "ana" }
        """)

        #expect(read[woodcase: .type] == .string("postit"))
        #expect(read[woodcase: .state] == .string("open"))
        #expect(read[woodcase: .author] == .string("claude"))
        #expect(read[woodcase: .tint] == .string("#FFF59D"))
        #expect(read[woodcase: .leaf] == .string("pODcm0"))
        #expect(read[woodcase: .stage] == .string("Capture"))
        #expect(read[woodcase: .copiedFrom] == .string("ana"))
    }

    @Test("Bare keys on metadata that is not a post-it's are not Woodcase's")
    func bareKeysElsewhereAreNotRead() throws {
        let read = try metadata(##"{ "type": "scratch", "state": "open", "author": "ana", "tint": "#FFFFFF" }"##)

        #expect(read[woodcase: .type] == nil)
        #expect(read[woodcase: .state] == nil)
        #expect(read[woodcase: .author] == nil)
        #expect(read[woodcase: .tint] == nil)
    }

    @Test("Where both spellings are present, the namespace wins")
    func namespaceWins() throws {
        let read = try metadata("""
        { "type": "postit", "state": "open", "_role": "card",
          "woodcase": { "state": "resolved", "role": "button" } }
        """)

        #expect(read[woodcase: .state] == .string("resolved"))
        #expect(read[woodcase: .role] == .string("button"))
    }

    @Test("Bare post-it keys still read once the namespace names the type")
    func bareKeysReadBesideNamespacedType() throws {
        let read = try metadata(#"{ "author": "claude", "woodcase": { "type": "postit" } }"#)

        #expect(read[woodcase: .author] == .string("claude"))
    }

    @Test("Keys with no old spelling read only from the namespace")
    func newKeysHaveNoOldSpelling() throws {
        let read = try metadata(#"{ "type": "postit", "anchor": "x", "fontSize": 20, "replyTo": "y" }"#)

        #expect(read[woodcase: .anchor] == nil)
        #expect(read[woodcase: .fontSize] == nil)
        #expect(read[woodcase: .replyTo] == nil)
    }

    // MARK: - Writing

    @Test("A write stores only the namespaced key and removes the old spelling")
    func writeRemovesOldSpelling() throws {
        var written = try metadata(#"{ "type": "component", "_role": "card", "_action": "go" }"#)

        written[woodcase: .role] = .string("button")

        #expect(try object(written) == [
            "type": .string("component"),
            "_action": .string("go"),
            "woodcase": .dictionary(["role": .string("button")]),
        ])
    }

    @Test("Writing the type of a legacy post-it rewrites type: postit to type: woodcase")
    func writingTypeRewritesLegacyType() throws {
        var written = try metadata(#"{ "type": "postit", "author": "claude" }"#)

        written[woodcase: .type] = .string("comment")

        #expect(written.type == PenMetadata.woodcaseType)
        #expect(written[woodcase: .author] == .string("claude"))
        #expect(written[woodcase: .type] == .string("comment"))
    }

    @Test("Writing nil removes both spellings, and an emptied namespace with them")
    func writingNilRemovesBoth() throws {
        var written = try metadata(#"{ "type": "component", "_role": "card", "woodcase": { "role": "button" } }"#)

        written[woodcase: .role] = nil

        #expect(try object(written) == ["type": .string("component")])
    }

    @Test("Writing a key leaves a bare key on non-post-it metadata alone")
    func writeLeavesForeignBareKey() throws {
        var written = try metadata(#"{ "type": "scratch", "author": "ana" }"#)

        written[woodcase: .author] = .string("claude")

        #expect(written.extensions["author"] == .string("ana"))
        #expect(written[woodcase: .author] == .string("claude"))
    }

    // MARK: - Old spellings and migration

    @Test("The old spellings a metadata object holds are listed by key")
    func listsOldSpellings() throws {
        let read = try metadata("""
        { "type": "postit", "state": "open", "kind": "question", "_role": "card",
          "woodcase": { "tint": "#FFFFFF" } }
        """)

        #expect(read.oldStyleWoodcaseKeys == [.role, .type, .state])
    }

    @Test("Migrating moves every old spelling into the namespace, the namespace winning, and keeps a legacy kind")
    func migratingConvertsEverything() throws {
        let read = try metadata("""
        { "type": "postit", "kind": "question", "state": "open", "author": "claude",
          "_role": "card", "woodcase": { "state": "resolved" } }
        """)

        let migrated = read.migratingOldStyleWoodcaseKeys()

        #expect(try object(migrated) == [
            "type": .string("woodcase"),
            "kind": .string("question"),
            "woodcase": .dictionary([
                "type": .string("postit"),
                "state": .string("resolved"),
                "author": .string("claude"),
                "role": .string("card"),
            ]),
        ])
        #expect(migrated.oldStyleWoodcaseKeys.isEmpty)
    }

    @Test("A write onto metadata with no type gives it type: woodcase")
    func writeOntoTypelessMetadataTypesIt() throws {
        var written = try metadata(#"{ "_role": "card" }"#)

        written[woodcase: .role] = .string("button")

        #expect(written.type == "woodcase")
    }

    @Test("Migrating typeless old-style metadata gives it type: woodcase")
    func migratingTypelessMetadataTypesIt() throws {
        let migrated = try metadata(#"{ "_role": "card" }"#).migratingOldStyleWoodcaseKeys()

        #expect(try object(migrated) == [
            "type": .string("woodcase"), "woodcase": .dictionary(["role": .string("card")]),
        ])
    }

    @Test("A type someone else wrote is never touched")
    func foreignTypeIsKept() throws {
        var written = try metadata(#"{ "type": "scratch", "_role": "card" }"#)
        written[woodcase: .tint] = .string("#FFFFFF")
        #expect(written.type == "scratch")
        #expect(written.migratingOldStyleWoodcaseKeys().type == "scratch")
    }

    @Test("Each key names its old spelling, or none")
    func keysNameOldSpellings() {
        #expect(PenMetadata.woodcaseNamespace == "woodcase")
        #expect(PenMetadata.WoodcaseKey.props.oldSpelling == "_props")
        #expect(PenMetadata.WoodcaseKey.scroll.oldSpelling == "_scroll")
        #expect(PenMetadata.WoodcaseKey.tint.oldSpelling == "tint")
        #expect(PenMetadata.WoodcaseKey.type.oldSpelling == "type")
        #expect(PenMetadata.WoodcaseKey.anchor.oldSpelling == nil)
        #expect(PenMetadata.WoodcaseKey.fontSize.oldSpelling == nil)
    }
}
