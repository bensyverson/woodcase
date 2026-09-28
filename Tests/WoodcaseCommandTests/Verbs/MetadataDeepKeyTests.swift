//
//  MetadataDeepKeyTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase set <node> common.metadata.<key>=<value>` — one key of the metadata
/// object, merged rather than replacing the object.
///
/// `common.metadata` is a whole-object property, so the only way to annotate a node
/// used to be to write the object out again — and every write that did so dropped
/// `_props`, `_role` and anything else already there. These are the tests that a deep
/// key merges, that the whole object still replaces, and that a null takes one key
/// away.
@Suite("woodcase set writes one metadata key")
struct MetadataDeepKeyTests {
    /// The metadata object a node carries, as the file writes it.
    private func metadata(of node: PenNode?) -> [String: AnyCodable] {
        guard let metadata = node?.common.metadata else { return [:] }
        var flat = metadata.extensions
        if let type = metadata.type {
            flat["type"] = .string(type)
        }
        return flat
    }

    @Test("A deep key merges into the object and leaves every sibling key alone")
    func aDeepKeyMerges() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "StatCard", "common.metadata._role=button", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        #expect(written["_role"] == .string("button"))
        #expect(written["type"] == .string("component"))
        guard case let .dictionary(props)? = written["_props"] else {
            Issue.record("_props was dropped: \(written)")
            return
        }
        #expect(props["label"] == .string("Body/Title"))
    }

    @Test("A deep key on a node with no metadata creates the object")
    func aDeepKeyCreatesTheObject() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("set", fixture.file.path, "Plain", "common.metadata._role=button")

        #expect(run.status == 0)
        #expect(try metadata(of: PenFileProbe(fixture.file).node("Plain"))["_role"] == .string("button"))
    }

    @Test("The object a deep key creates carries the schema's required type, defaulted")
    func aCreatedObjectCarriesTheRequiredType() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("set", fixture.file.path, "Plain", "common.metadata._role=button")

        #expect(run.status == 0)
        // `type` is required by the .pen schema (Pen-Schema-2.17 line 105), so an object
        // the fold creates has to carry one; "unknown" is PenMetadata's default.
        #expect(try metadata(of: PenFileProbe(fixture.file).node("Plain"))["type"] == .string("unknown"))
    }

    @Test("Two deep keys in one write choose the metadata type as well as the role")
    func twoDeepKeysChooseTheTypeAndTheRole() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "Plain",
            "common.metadata.type=component", "common.metadata._role=button"
        )

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let written = try metadata(of: PenFileProbe(fixture.file).node("Plain"))
        #expect(written == ["type": .string("component"), "_role": .string("button")])
    }

    @Test("A nested deep key declares one parameter without rewriting the rest")
    func aNestedDeepKeyDeclaresAParameter() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "StatCard", "common.metadata._props.caption=Body/Title"
        )

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        guard case let .dictionary(props)? = written["_props"] else {
            Issue.record("_props is not an object: \(written)")
            return
        }
        #expect(props["caption"] == .string("Body/Title"))
        #expect(props["label"] == .string("Body/Title"))
    }

    @Test("A deep key set to null removes that key and keeps the others")
    func aNullDeepKeyRemovesOneKey() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let seeded = try fixture.run("set", fixture.file.path, "StatCard", "common.metadata._role=button")
        #expect(seeded.status == 0)

        let run = try fixture.run("set", fixture.file.path, "StatCard", "common.metadata._role=null")

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        #expect(written["_role"] == nil)
        #expect(written["_props"] != nil)
        #expect(written["type"] == .string("component"))
    }

    @Test("A nested deep key set to null removes one declared parameter")
    func aNullNestedDeepKeyRemovesOneParameter() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "StatCard", "common.metadata._props.gone=null"
        )

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        guard case let .dictionary(props)? = written["_props"] else {
            Issue.record("_props is not an object: \(written)")
            return
        }
        #expect(props["gone"] == nil)
        #expect(props["label"] == .string("Body/Title"))
    }

    @Test("The whole object still replaces what was there")
    func theWholeObjectStillReplaces() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "StatCard", #"common.metadata={"type":"component"}"#
        )

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        #expect(written["type"] == .string("component"))
        #expect(written["_props"] == nil)
    }

    @Test("A deep key given with the whole object merges onto it")
    func aDeepKeyMergesOntoAWholeObject() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "set", fixture.file.path, "StatCard",
            #"common.metadata={"type":"component"}"#, "common.metadata._role=button"
        )

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        #expect(written["type"] == .string("component"))
        #expect(written["_role"] == .string("button"))
        #expect(written["_props"] == nil)
    }

    @Test("A deep key through a batch set means the same thing")
    func aBatchSetTakesDeepKeys() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let batch = fixture.root.appendingPathComponent("batch.jsonl")
        try #"{"op":"set","target":"StatCard","props":{"common.metadata._role":"button"}}"#
            .write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path)

        #expect(run.status == 0)
        let written = try metadata(of: PenFileProbe(fixture.file).node("StatCard"))
        #expect(written["_role"] == .string("button"))
        #expect(written["_props"] != nil)
    }

    @Test("Only metadata takes a deep key: another property refuses one, naming it")
    func onlyMetadataTakesADeepKey() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("set", fixture.file.path, "StatCard", "common.name.first=Hi")

        #expect(run.status != 0)
        #expect(run.stderr.contains("common.name.first"))
    }

    @Test("set --help says the whole object replaces and a deep key merges")
    func theHelpSaysBoth() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("set", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("common.metadata.<key>"))
        #expect(run.stdout.contains("REPLACES"))
        // The defaulted `type` is a surprise unless the help names it, so it says how to
        // choose one instead. One token, because the discussion is wrapped to the width.
        #expect(run.stdout.contains("common.metadata.type=component"))
    }

    @Test("The schema row for metadata says a deep key writes one entry")
    func theSchemaRowSaysSo() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("schema")

        #expect(run.status == 0)
        #expect(run.stdout.contains("common.metadata."))
    }
}
