//
//  FuzzFixture+Merge.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

extension FuzzFixture {
    /// The top-level containers of ``mergeDocument()`` that share nothing: each holds its
    /// own component and every instance of it, so edits scoped to one never reach the other.
    static let disjointScopes = ["L", "R"]

    /// A base document for merge fuzzing: two self-contained subtrees `L` and `R`, each
    /// with a component, instances (one with a descendant override), nested containers
    /// and a frame declaring `"children": []`; top-level nodes beside them; and a root
    /// with a variable, a theme axis, a declared-empty import table and a root extra.
    static func mergeDocument() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(#"""
        {"version":"2.20","themes":{"mode":["light","dark"]},
         "variables":{"accent":{"type":"color","value":"#FF0000"}},
         "imports":{},"rootNote":"kept",
         "children":[\#(side("L")),\#(side("R")),
           {"type":"rectangle","id":"top","width":10,"height":10,"futureKey":1},
           {"type":"frame","id":"box","width":40}]}
        """#))
    }

    /// One self-contained subtree, every id prefixed with `p`.
    private static func side(_ p: String) -> String {
        #"""
        {"type":"frame","id":"\#(p)","width":400,"children":[
          {"type":"frame","id":"\#(p)c","reusable":true,"width":100,"children":[
            {"type":"text","id":"\#(p)c1","content":"Label"},
            {"type":"rectangle","id":"\#(p)c2","width":24,"height":24}]},
          {"type":"ref","id":"\#(p)i1","ref":"\#(p)c"},
          {"type":"ref","id":"\#(p)i2","ref":"\#(p)c","descendants":{"\#(p)c1":{"content":"Cancel"}}},
          {"type":"frame","id":"\#(p)f","width":200,"children":[
            {"type":"rectangle","id":"\#(p)r1","width":10,"height":10},
            {"type":"group","id":"\#(p)g","children":[
              {"type":"rectangle","id":"\#(p)r2","width":20,"height":20},
              {"type":"text","id":"\#(p)t","content":"Hi"}]}]},
          {"type":"frame","id":"\#(p)e","width":50,"children":[]}]}
        """#
    }
}
