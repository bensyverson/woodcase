//
//  PenConnectionIndexTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The node → connections index: given the nodes an edit moved, resized or replaced, the
/// connections whose routes must be redrawn — those attached to a changed node, to a
/// descendant of one (which moves with it), or into an instance whose expansion it
/// changes.
struct PenConnectionIndexTests {
    /// `Page` holds `Card`, which holds `Title`; `Other` is a rectangle; `Inst` is an
    /// instance of `Comp`, whose child is `Label`. `C1` joins `Title` to `Other`, `C2`
    /// `Other` to `Inst/Label`, `C3` `Ghost` (no such node) to `Page`.
    private static let json = """
    {"version":"2.20","children":[
      {"id":"Page","type":"frame","layout":"none","x":0,"y":0,"width":400,"height":300,"children":[
        {"id":"Card","type":"frame","layout":"none","x":20,"y":20,"width":200,"height":100,"children":[
          {"id":"Title","type":"text","x":10,"y":10,"content":"Hi"}]}]},
      {"id":"Other","type":"rectangle","x":500,"y":0,"width":40,"height":40},
      {"id":"Comp","type":"frame","reusable":true,"layout":"none","x":0,"y":400,"width":100,"height":40,"children":[
        {"id":"Label","type":"text","x":4,"y":4,"content":"L"}]},
      {"id":"Inst","type":"ref","ref":"Comp","x":600,"y":0},
      {"id":"C1","type":"connection","source":{"path":"Title","anchor":"right"},"target":{"path":"Other","anchor":"left"}},
      {"id":"C2","type":"connection","source":{"path":"Other","anchor":"bottom"},"target":{"path":"Inst/Label","anchor":"top"}},
      {"id":"C3","type":"connection","source":{"path":"Ghost","anchor":"right"},"target":{"path":"Page","anchor":"left"}}]}
    """

    private func index() throws -> PenConnectionIndex {
        try PenConnectionIndex(PenParser.parse(Data(Self.json.utf8)))
    }

    @Test("The index lists every connection, in document order")
    func lists() throws {
        #expect(try index().connectionIDs == ["C1", "C2", "C3"])
    }

    @Test("A moved endpoint redraws the connections attached to it")
    func directEndpoint() throws {
        let index = try index()
        #expect(index.connections(affectedBy: ["Other"]) == ["C1", "C2"])
        #expect(index.connections(attachedTo: "Other") == ["C1", "C2"])
        #expect(index.connections(attachedTo: "Card").isEmpty, "attached means named as an endpoint")
    }

    @Test("A moved ancestor redraws the connections attached to its descendants")
    func ancestor() throws {
        let index = try index()
        #expect(index.connections(affectedBy: ["Card"]) == ["C1"])
        #expect(index.connections(affectedBy: ["Page"]) == ["C1", "C3"])
    }

    @Test("A moved instance, or a change inside its component, redraws connections into it")
    func instance() throws {
        let index = try index()
        #expect(index.connections(affectedBy: ["Inst"]) == ["C2"])
        #expect(index.connections(affectedBy: ["Label"]) == ["C2"])
        #expect(index.connections(affectedBy: ["Comp"]) == ["C2"])
    }

    @Test("A changed connection redraws itself; a node nothing joins redraws nothing")
    func selfAndUnrelated() throws {
        let index = try index()
        #expect(index.connections(affectedBy: ["C2"]) == ["C2"])
        #expect(index.connections(affectedBy: ["Nothing"]).isEmpty)
    }

    @Test("A node added under a name an endpoint already names redraws that connection")
    func danglingEndpoint() throws {
        #expect(try index().connections(affectedBy: ["Ghost"]) == ["C3"])
    }

    @Test("Several changes list each connection once, in document order")
    func union() throws {
        #expect(try index().connections(affectedBy: ["Inst", "Title", "Other"]) == ["C1", "C2"])
    }
}
