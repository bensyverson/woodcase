//
//  ThreeWayEdgeCaseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The three-way merge's rules where two of them meet: a retype against a kind edit, a
/// whole-node override, a component under a deleted container.
@MainActor
struct ThreeWayEdgeCaseTests {
    private typealias F = MergeFixture

    private let component = #"{"type":"frame","id":"comp","reusable":true,"children":[{"type":"text","id":"label","content":"A"}]}"#

    @Test("Ours retyped a node theirs edited a kind key of: ours' type stays, reported once")
    func oursRetypedTheirsEditedKind() throws {
        let result = try F.resolve(
            base: F.frame("page", F.rect("x")),
            ours: F.frame("page", #"{"type":"ellipse","id":"x","width":10,"height":10}"#),
            theirs: F.frame("page", #"{"type":"rectangle","id":"x","width":30,"height":40}"#)
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts == [MergeConflict(
            subject: .nodeType(nodeID: "x"), kind: .bothChanged,
            base: .string("rectangle"), ours: .string("ellipse"), theirs: .string("rectangle")
        )])
    }

    @Test("A whole-node descendant replacement merges as one value")
    func objectReplacementOverride() throws {
        let instance = { (descendants: String) in
            F.frame("page", #"\#(component),{"type":"ref","id":"inst","ref":"comp","descendants":{\#(descendants)}}"#)
        }
        let ours = #""label":{"type":"text","id":"label","content":"Ours"}"#
        let theirs = #""label":{"type":"text","id":"label","content":"Theirs"}"#
        let result = try F.resolve(base: instance(""), ours: instance(ours), theirs: instance(theirs))
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts.map(\.subject) == [.descendantOverride(nodeID: "inst", descendant: "label", key: nil)])
        #expect(result.conflicts.first?.base == nil)
    }

    @Test("A root override theirs removed is removed")
    func rootOverrideRemoved() throws {
        let instance = { (members: String) in
            F.frame("page", #"\#(component),{"type":"ref","id":"inst","ref":"comp"\#(members)}"#)
        }
        let result = try F.resolve(base: instance(#","width":50"#), ours: instance(#","width":50"#), theirs: instance(""))
        guard case let .ref(ref)? = result.nodes["inst"]?.node.kind else {
            Issue.record("the instance should change")
            return
        }
        #expect(ref.rootOverrides == nil)
    }

    @Test("A component kept for a local instance keeps the container theirs deleted around it")
    func componentKeptWithItsContainer() throws {
        let library = F.frame("library", component)
        let instance = #"{"type":"ref","id":"inst","ref":"comp"}"#
        let result = try F.resolve(
            base: "\(library),\(F.frame("page"))",
            ours: "\(library),\(F.frame("page", instance))",
            theirs: F.frame("page")
        )
        #expect(result.removed.isEmpty)
        #expect(result.rootOrder == nil, "library stays where ours has it")
        #expect(result.conflicts == [
            MergeConflict(subject: .existence(nodeID: "comp"), kind: .componentKeptForLocalInstance),
            MergeConflict(subject: .existence(nodeID: "library"), kind: .componentKeptForLocalInstance),
        ])
    }

    @Test("An insert under another dropped insert follows it silently")
    func nestedOrphans() throws {
        let result = try F.resolve(
            base: F.frame("page", F.frame("card")),
            ours: F.frame("page"),
            theirs: F.frame("page", F.frame("card", F.frame("n", F.frame("m", F.rect("leaf")))))
        )
        #expect(result.nodes.isEmpty)
        #expect(result.conflicts.map(\.subject) == [.existence(nodeID: "n")])
    }
}
