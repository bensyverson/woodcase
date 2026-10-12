//
//  NodePropertyCodecDeepReadTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Reading one key inside `common.metadata` by a deep key, the same form `set` writes:
/// `common.metadata.woodcase.author`. A Woodcase key reads through
/// ``PenMetadata/subscript(woodcase:)``, so either spelling answers; an absent key reads
/// as null, never as "not a property".
struct NodePropertyCodecDeepReadTests {
    private func node(_ json: String) throws -> PenNode {
        try JSONDecoder().decode(PenNode.self, from: Data(json.utf8))
    }

    private var namespaced: PenNode {
        get throws {
            try node(##"""
            { "id": "Nte01", "type": "note", "content": "hi",
              "metadata": { "type": "woodcase",
                            "woodcase": { "author": "ana", "leaf": "Wq5asV",
                                          "props": { "label": "Body/Title" } },
                            "vendor": { "flag": true } } }
            """##)
        }
    }

    private var oldStyle: PenNode {
        get throws {
            try node(##"""
            { "id": "Nte02", "type": "note", "content": "hi",
              "metadata": { "type": "postit", "author": "claude", "leaf": "pODcm0" } }
            """##)
        }
    }

    @Test("A namespaced deep key reads its value")
    func readsNamespacedKey() throws {
        let note = try namespaced
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.author", of: note) == .string("ana"))
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.leaf", of: note) == .string("Wq5asV"))
    }

    @Test("A deep key reaches inside a nested object")
    func readsNestedKey() throws {
        #expect(
            try NodePropertyCodec.value(at: "common.metadata.woodcase.props.label", of: namespaced)
                == .string("Body/Title")
        )
        #expect(try NodePropertyCodec.value(at: "common.metadata.vendor.flag", of: namespaced) == .bool(true))
    }

    @Test("A namespaced deep key reads the old spelling on an old-style post-it")
    func namespacedKeyReadsOldSpelling() throws {
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.author", of: oldStyle) == .string("claude"))
    }

    @Test("An old spelling reads the namespaced value where the namespace holds it")
    func oldSpellingReadsNamespace() throws {
        let typed = try node(##"""
        { "id": "Cm01", "type": "note", "content": "hi",
          "metadata": { "type": "woodcase", "woodcase": { "type": "comment", "leaf": "Wq5asV" } } }
        """##)
        #expect(try NodePropertyCodec.value(at: "common.metadata.leaf", of: typed) == .string("Wq5asV"))
        #expect(try NodePropertyCodec.value(at: "common.metadata.leaf", of: oldStyle) == .string("pODcm0"))
    }

    @Test("An absent deep key reads as null, on a node with metadata or without")
    func absentReadsNull() throws {
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.tint", of: namespaced) == .null)
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.props.missing", of: namespaced) == .null)
        let bare = try node(##"{ "id": "Nte03", "type": "note", "content": "" }"##)
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.author", of: bare) == .null)
    }
}
