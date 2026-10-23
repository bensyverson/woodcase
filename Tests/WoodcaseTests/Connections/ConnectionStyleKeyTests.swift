//
//  ConnectionStyleKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A connection's routing and arrowheads: three `metadata.woodcase` keys, written at
/// `kind.routing`, `kind.startArrowhead` and `kind.endArrowhead` (Penumbra ruling R11).
/// Pen drops a connection entirely when it opens a file, so they are Woodcase's alone;
/// a file without them draws as it always did, straight and bare.
@MainActor
struct ConnectionStyleKeyTests {
    private static let json = """
    {"version":"2.20","children":[
      {"id":"A","type":"rectangle","x":0,"y":0,"width":40,"height":20},
      {"id":"B","type":"rectangle","x":100,"y":60,"width":40,"height":20},
      {"id":"C","type":"connection","source":{"path":"A","anchor":"right"},
       "target":{"path":"B","anchor":"left"},"stroke":"#FF0000","strokeWidth":2}]}
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(Self.json.utf8)))
    }

    private func set(_ values: [String: AnyCodable], on id: String, in document: EditableDocument) throws {
        let plan = try EditPlanner.plan(.set(values), at: PlannerFixture.address("#\(id)"), in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
    }

    private typealias Key = PenMetadata.WoodcaseKey

    @Test("The three keys are connector keys, each one of a closed set of spellings")
    func vocabulary() {
        #expect(Key.routing.group == .connector)
        #expect(Key.startArrowhead.group == .connector)
        #expect(Key.endArrowhead.group == .connector)
        #expect(Key.routing.shape == .oneOf(["straight", "elbow"]))
        #expect(Key.startArrowhead.shape == .oneOf(["none", "triangle", "chevron", "circle"]))
        #expect(Key.endArrowhead.shape == Key.startArrowhead.shape)
        for key in [Key.routing, .startArrowhead, .endArrowhead] {
            #expect(key.oldSpelling == nil)
            #expect(key.naturalPathTypes == [.connection])
            #expect(key.storagePathRule == .refused)
            #expect(!key.summary.isEmpty)
        }
        #expect(Key.routing.propertyPath == "kind.routing")
        #expect(Key.startArrowhead.propertyPath == "kind.startArrowhead")
        #expect(Key.endArrowhead.propertyPath == "kind.endArrowhead")
    }

    @Test("A connection with no keys is straight with no arrowheads, as every file drew before")
    func defaults() throws {
        let node = try #require(document().node(id: "C"))
        #expect(node.connectionStyle == PenNode.ConnectionData.Style.plain)
        #expect(node.connectionStyle?.routing == .straight)
        #expect(node.connectionStyle?.startArrowhead == PenNode.ConnectionData.Arrowhead.none)
        #expect(node.connectionStyle?.endArrowhead == PenNode.ConnectionData.Arrowhead.none)
    }

    @Test("A node that is not a connection has no connection style")
    func notAConnection() throws {
        #expect(try document().node(id: "A")?.connectionStyle == nil)
    }

    @Test("A new connector's style is spec §11.2's: elbow, an arrowhead at the target end")
    func newConnectorStyle() {
        let style = PenNode.ConnectionData.Style.newConnector
        #expect(style.routing == .elbow)
        #expect(style.startArrowhead == PenNode.ConnectionData.Arrowhead.none)
        #expect(style.endArrowhead == .triangle)
    }

    @Test("Writing kind.routing and the arrowheads stores them in metadata.woodcase")
    func writesThroughNaturalPaths() throws {
        let document = try document()
        try set(
            ["kind.routing": "elbow", "kind.startArrowhead": "circle", "kind.endArrowhead": "triangle"],
            on: "C", in: document
        )
        let node = try #require(document.node(id: "C"))
        #expect(node.common.metadata?[woodcase: .routing] == .string("elbow"))
        #expect(node.common.metadata?[woodcase: .endArrowhead] == .string("triangle"))
        #expect(node.connectionStyle == PenNode.ConnectionData.Style(
            routing: .elbow, startArrowhead: .circle, endArrowhead: .triangle
        ))
    }

    @Test("A spelling outside the set is refused as the wrong form")
    func refusesUnknownSpelling() throws {
        let document = try document()
        #expect(PlannerFixture.refusal(.set(["kind.routing": "curved"]), at: "#C", in: document)?.code == .invalidForm)
        #expect(PlannerFixture.refusal(.set(["kind.endArrowhead": "arrow"]), at: "#C", in: document)?.code
            == .invalidForm)
    }

    @Test("Another node type does not take the keys")
    func refusedOnOtherTypes() throws {
        let document = try document()
        #expect(PlannerFixture.refusal(.set(["kind.routing": "elbow"]), at: "#A", in: document) != nil)
    }

    @Test("The storage path is refused, naming the natural path")
    func storagePathRefused() throws {
        let document = try document()
        let refusal = PlannerFixture.refusal(
            .set(["common.metadata.woodcase.routing": "elbow"]), at: "#C", in: document
        )
        #expect(refusal != nil)
    }

    @Test("The keys round-trip through the file")
    func roundTrips() throws {
        let document = try document()
        try set(["kind.routing": "elbow", "kind.endArrowhead": "chevron"], on: "C", in: document)
        let data = try PenParser.encode(document.materialize())
        let reread = try EditableDocument(from: PenParser.parse(data))
        let style = try #require(reread.node(id: "C")?.connectionStyle)
        #expect(style == PenNode.ConnectionData.Style(routing: .elbow, startArrowhead: .none, endArrowhead: .chevron))
    }

    @Test("A spelling a file holds that Woodcase does not know draws as the default")
    func unknownSpellingInAFile() throws {
        let json = Self.json.replacingOccurrences(
            of: #""strokeWidth":2}"#,
            with: #""strokeWidth":2,"metadata":{"type":"woodcase","woodcase":{"routing":"curved","endArrowhead":7}}}"#
        )
        let node = try #require(EditableDocument(from: PenParser.parse(Data(json.utf8))).node(id: "C"))
        #expect(node.connectionStyle == PenNode.ConnectionData.Style.plain)
    }

    @Test("Only a connection publishes the three keys as schema fields, with their defaults")
    func schemaFields() throws {
        let routing = try #require(PenSchema.field("kind.routing", for: .connection))
        #expect(routing.default == .string("straight"))
        #expect(routing.key.written == "metadata.woodcase.routing")
        let end = try #require(PenSchema.field("kind.endArrowhead", for: .connection))
        #expect(end.default == .string("none"))
        #expect(PenSchema.field("kind.startArrowhead", for: .connection)?.default == .string("none"))
        for type in PenNode.NodeType.allCases where type != .connection {
            #expect(PenSchema.field("kind.routing", for: type) == nil, "\(type)")
        }
    }
}
