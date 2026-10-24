//
//  PenRefExpanderInstancePathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which expanded nodes are instance roots, and the path an authored reference names each
/// by — read off the expanded ids, as the expander writes them.
struct PenRefExpanderInstancePathTests {
    @Test("A top-level instance's root is named by its ref's id", arguments: [nil, "Board"])
    func topLevel(parent: String?) {
        #expect(PenRefExpander.instancePath(ofExpandedID: "Chip/Comp", parentID: parent) == "Chip")
    }

    @Test("A node inside an instance is no instance root")
    func descendant() {
        #expect(PenRefExpander.instancePath(ofExpandedID: "Chip/Label", parentID: "Chip/Comp") == nil)
        #expect(PenRefExpander.instancePath(ofExpandedID: "Chip/Deep", parentID: "Chip/Inner") == nil)
    }

    @Test("An instance in a slot fill or a component's tree is named by its instance path")
    func nested() {
        #expect(PenRefExpander.instancePath(ofExpandedID: "Filled/Row1/Item", parentID: "Filled/Body") == "Filled/Row1")
        #expect(PenRefExpander.instancePath(ofExpandedID: "P/PScr/Screen", parentID: "P/Panel") == "P/PScr")
        #expect(PenRefExpander.instancePath(ofExpandedID: "Filled/Row1/ALbl", parentID: "Filled/Row1/Item") == nil)
    }

    @Test("A plain node is no instance root")
    func plain() {
        #expect(PenRefExpander.instancePath(ofExpandedID: "Board", parentID: nil) == nil)
        #expect(PenRefExpander.instancePath(ofExpandedID: "Card", parentID: "Board") == nil)
    }

    @Test("Every instance root of an expanded document is found, and nothing else")
    func wholeDocument() throws {
        let json = #"""
        {"version":"2.19","children":[
          {"id":"Item","type":"frame","reusable":true,"width":40,"height":20,"layout":"none",
           "children":[{"id":"ALbl","type":"rectangle","width":4,"height":4}]},
          {"id":"Host","type":"frame","reusable":true,"width":100,"height":60,"layout":"none",
           "children":[{"id":"Body","type":"frame","slot":[],"width":100,"height":60,"layout":"none"},
                       {"id":"Fixed","type":"ref","ref":"Item"}]},
          {"id":"Filled","type":"ref","ref":"Host","descendants":{"Body":{"children":[
            {"id":"Row1","type":"ref","ref":"Item"}]}}}]}
        """#
        let document = try PenRefExpander.expand(PenParser.parse(json))

        #expect(PenLayoutEngine.instancePaths(in: document) == [
            "Filled": "Filled/Host", "Filled/Row1": "Filled/Row1/Item", "Filled/Fixed": "Filled/Fixed/Item",
        ])
    }
}
