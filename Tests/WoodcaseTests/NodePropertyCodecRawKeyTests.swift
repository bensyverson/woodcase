//
//  NodePropertyCodecRawKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The bridge between the two property vocabularies: the dotted paths every read
/// and `set` speak, and the raw .pen names a component instance's `descendants`
/// map is keyed in.
struct NodePropertyCodecRawKeyTests {
    @Test(
        "A dotted path becomes the .pen key it is stored under",
        arguments: [
            ("kind.content", "content"),
            ("common.name", "name"),
            ("common.x", "x"),
            ("kind.width", "width"),
            ("kind.fills", "fill"),
            ("kind.effects", "effect"),
        ]
    )
    func pathsBecomeRawKeys(path: String, key: String) {
        #expect(NodePropertyCodec.rawKey(for: path) == key)
    }

    @Test("A name that is already raw is left alone", arguments: ["content", "fill", "name"])
    func rawNamesArePassedThrough(key: String) {
        #expect(NodePropertyCodec.rawKey(for: key) == key)
    }

    @Test("A whole set of properties is rekeyed at once")
    func rekeysASetOfProperties() {
        let raw = NodePropertyCodec.rawKeyed([
            "kind.content": .string("Hi"),
            "common.name": .string("Tag"),
            "fill": .string("#FF0000"),
        ])
        #expect(raw == ["content": .string("Hi"), "name": .string("Tag"), "fill": .string("#FF0000")])
    }
}
