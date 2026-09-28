//
//  NodeLookupExpansionTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// ``NodeLookup`` answering for a node that has no post-expansion id of its own.
///
/// A `ref` does not survive ``PenRefExpander/expand(_:for:)`` under its own
/// id: the expander clones the component it points at and prefixes every id in the
/// clone with the ref's, so the instance placed by `Bdg01` is rooted at `Bdg01/Bge01`.
/// Mapping the authored address onto that id is
/// ``Woodcase/EditableDocument/expandedID(of:)``'s job, and this suite pins the answer
/// for the shapes `addressing.pen` carries — in particular a ref nested *inside* a
/// component definition, which is reached both through the definition and through every
/// instance of it.
@Suite("NodeLookup and ref expansion")
struct NodeLookupExpansionTests {
    @MainActor
    @Test("A ref nested inside a component resolves to the component root it clones")
    func refInsideAComponent() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        // `Bdg01` is a ref to `Bge01`, and it lives inside the reusable `Btn01`.
        let run = try fixture.run("get", fixture.file.path, "Bdg01", "--expand", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let node = try Self.node(in: run.stdout)
        #expect(node.id == "Bdg01/Bge01")
        #expect(node.common.name == "Badge")
    }

    @MainActor
    @Test("The same ref reached through an instance carries the instance's prefix")
    func refInsideAnInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")

        // `Nav01` places `Btn01`, so its copy of `Bdg01` is `Nav01/Bdg01`.
        let run = try fixture.run("get", fixture.file.path, "Nav01/Bdg01", "--expand", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let node = try Self.node(in: run.stdout)
        #expect(node.id == "Nav01/Bdg01/Bge01")
        // The instance's override reached the nested instance's child.
        #expect(node.kind.inlineChildren.first?.id == "Nav01/Bdg01/Cnt01")
    }

    @MainActor
    @Test("A top-level instance resolves to its component's root, not to the ref id")
    func topLevelInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("get", fixture.file.path, "Nav01", "--expand", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.node(in: run.stdout).id == "Nav01/Btn01")
    }

    @MainActor
    @Test("A node inside an instance keeps the id the expander wrote for it")
    func nodeInsideAnInstance() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("get", fixture.file.path, "Nav01/Lbl01", "--expand", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        let node = try Self.node(in: run.stdout)
        #expect(node.id == "Nav01/Lbl01")
        #expect(node.common.name == "Label")
    }

    @MainActor
    @Test("A plain node is its own expanded id")
    func plainNode() throws {
        let fixture = try CommandFixture(fixture: "addressing.pen")
        let run = try fixture.run("get", fixture.file.path, "Ttl01", "--expand", "--json")
        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Self.node(in: run.stdout).id == "Ttl01")
    }

    /// The `node` object out of `get --json`.
    private static func node(in stdout: String) throws -> PenNode {
        struct Payload: Decodable {
            let node: PenNode
        }
        return try JSONDecoder().decode(Payload.self, from: Data(stdout.utf8)).node
    }
}
