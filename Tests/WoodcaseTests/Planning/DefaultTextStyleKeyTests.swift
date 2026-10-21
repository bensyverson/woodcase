//
//  DefaultTextStyleKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `metadata.woodcase.defaultTextStyle`: the mark that makes a text the document's default
/// text style, since `.pen` has no document-level metadata (Penumbra spec §6.3, Ben's
/// ruling of 2026-10-18). Pen keeps node metadata.
@MainActor
struct DefaultTextStyleKeyTests {
    private static let path = DefaultTextStyleFixture.path

    @Test("The key is editor state, a boolean, with no old spelling")
    func vocabulary() {
        let key = PenMetadata.WoodcaseKey.defaultTextStyle
        #expect(key.rawValue == "defaultTextStyle")
        #expect(key.group == .editor)
        #expect(key.shape == .boolean)
        #expect(key.spellings == ["true", "false"])
        #expect(key.oldSpelling == nil)
        #expect(key.summary.contains("default text style"))
        #expect(key.path == "common.metadata.woodcase.defaultTextStyle")
    }

    @Test("A boolean is stored in the namespace; anything else is the wrong form")
    func onlyABoolean() throws {
        let document = try DefaultTextStyleFixture.document()
        #expect(PlannerFixture.refusal(.set([Self.path: "yes"]), at: "#Body", in: document)?.code == .invalidForm)
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        let node = try #require(document.node(id: "Body"))
        #expect(node.common.metadata?[woodcase: .defaultTextStyle] == .bool(true))
    }

    @Test("A write keeps the node's other metadata")
    func keepsOtherMetadata() throws {
        let document = try DefaultTextStyleFixture.document()
        let role = PenMetadata.WoodcaseKey.role.propertyPath
        let plan = try EditPlanner.plan(.set([role: "heading"]), at: PlannerFixture.address("#Body"), in: document)
        try DefaultTextStyleFixture.apply(plan.operations, to: document)
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        let metadata = try #require(document.node(id: "Body")?.common.metadata)
        #expect(metadata[woodcase: .role] == .string("heading"))
        #expect(metadata[woodcase: .defaultTextStyle] == .bool(true))
    }

    @Test("The key round-trips through the file")
    func roundTrips() throws {
        let document = try DefaultTextStyleFixture.document()
        try DefaultTextStyleFixture.write(true, on: ["Body"], in: document)
        let data = try PenParser.encode(document.materialize())
        let reread = try EditableDocument(from: PenParser.parse(data))
        #expect(reread.node(id: "Body")?.common.metadata?[woodcase: .defaultTextStyle] == .bool(true))
        #expect(String(decoding: data, as: UTF8.self).contains(#""defaultTextStyle":true"#))
    }

    @Test("Only a text publishes the key as a schema field, unset meaning not the default")
    func schemaFieldOnText() throws {
        let row = try #require(PenSchema.field(Self.path, for: .text))
        #expect(row.default == .boolean(false))
        #expect(row.key.written == "metadata.woodcase.defaultTextStyle")
        for type in PenNode.NodeType.allCases where type != .text {
            #expect(PenSchema.field(Self.path, for: type) == nil, "\(type)")
        }
    }
}
