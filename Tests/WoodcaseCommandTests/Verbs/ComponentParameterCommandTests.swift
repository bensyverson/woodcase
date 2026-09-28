//
//  ComponentParameterCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A component's `common.metadata._props` read as its parameter list, by the verbs
/// that write to an instance and the verb that reads one.
///
/// Codegen has always read `_props` as prop name → descendant name path. Nothing new
/// enters the format here: the same declaration becomes a key `override` and `cp`
/// accept, and a list `get` prints, so the name a component publishes is the name an
/// agent writes.
@Suite("A component's declared parameters")
struct ComponentParameterCommandTests {
    /// The overrides an instance stores, keyed by descendant key.
    private func descendants(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    /// The root overrides an instance carries.
    private func rootOverrides(of instance: PenNode?) -> [String: AnyCodable] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.rootOverrides ?? [:]
    }

    // MARK: - override

    @Test("A declared parameter name lands on the descendant it names")
    func aParameterNameLandsOnItsDescendant() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("override", fixture.file.path, "Page/Card", "label=Hi", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let stored = try descendants(of: PenFileProbe(fixture.file).node("Page/Card"))
        #expect(stored["Ttl01"]?.properties["content"] == .string("Hi"))
    }

    @Test("A parameter whose target takes a fill is written as that node's fill")
    func aColourParameterWritesAFill() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("override", fixture.file.path, "Page/Card", "tint=#112233")

        #expect(run.status == 0)
        let stored = try descendants(of: PenFileProbe(fixture.file).node("Page/Card"))
        #expect(stored["Swt01"]?.properties["fill"] == .string("#112233"))
    }

    @Test("A parameter whose path resolves to nothing is refused, naming both")
    func anUnresolvableParameterIsRefused() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("override", fixture.file.path, "Page/Card", "gone=Hi")

        #expect(run.status != 0)
        #expect(run.stderr.contains("gone"))
        #expect(run.stderr.contains("Body/Missing"))
        #expect(try descendants(of: PenFileProbe(fixture.file).node("Page/Card")).isEmpty)
    }

    @Test("A parameter name that is also a raw property is written as the raw property")
    func aCollidingNameIsTheRawProperty() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("override", fixture.file.path, "Page/Card", "width=320")

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(rootOverrides(of: probe.node("Page/Card"))["width"] == .int(320))
        #expect(descendants(of: probe.node("Page/Card")).isEmpty)
        #expect(run.stdout.contains("width"))
        #expect(run.stdout.contains("Body/Title"))
    }

    @Test("An undeclared key that is no property still stores as an override")
    func anUndeclaredKeyIsUnchanged() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("override", fixture.file.path, "Page/Card", "nonsense=Hi")

        #expect(run.status == 0)
        #expect(try rootOverrides(of: PenFileProbe(fixture.file).node("Page/Card"))["nonsense"] == .string("Hi"))
    }

    @Test("A batch override takes a parameter name too")
    func aBatchOverrideTakesAParameterName() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let batch = fixture.root.appendingPathComponent("batch.jsonl")
        try #"{"op":"override","target":"Page/Card","props":{"label":"Hi"}}"#
            .write(to: batch, atomically: true, encoding: .utf8)

        let run = try fixture.run("apply", fixture.file.path, "-F", batch.path)

        #expect(run.status == 0)
        let stored = try descendants(of: PenFileProbe(fixture.file).node("Page/Card"))
        #expect(stored["Ttl01"]?.properties["content"] == .string("Hi"))
    }

    // MARK: - cp

    @Test("A cp argv key may be a parameter name")
    func aCopyTakesAParameterName() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "StatCard", "Page", "common.name=Solo", "label=Solo title"
        )

        #expect(run.status == 0)
        let stored = try descendants(of: PenFileProbe(fixture.file).node("Page/Solo"))
        #expect(stored["Ttl01"]?.properties["content"] == .string("Solo title"))
    }

    @Test("A cp --each row may be keyed by a parameter name")
    func eachRowsTakeParameterNames() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let rows = fixture.root.appendingPathComponent("rows.jsonl")
        try """
        {"common.name":"One","label":"First"}
        {"common.name":"Two","label":"Second"}
        """.write(to: rows, atomically: true, encoding: .utf8)

        let run = try fixture.run("cp", fixture.file.path, "StatCard", "Page", "--each", rows.path)

        #expect(run.status == 0)
        let probe = try PenFileProbe(fixture.file)
        #expect(descendants(of: probe.node("Page/One"))["Ttl01"]?.properties["content"] == .string("First"))
        #expect(descendants(of: probe.node("Page/Two"))["Ttl01"]?.properties["content"] == .string("Second"))
    }

    @Test("A cp row naming an unresolvable parameter refuses the whole run")
    func anUnresolvableParameterRefusesTheCopy() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")
        let rows = fixture.root.appendingPathComponent("rows.jsonl")
        try """
        {"common.name":"One","label":"First"}
        {"common.name":"Two","gone":"Second"}
        """.write(to: rows, atomically: true, encoding: .utf8)

        let run = try fixture.run("cp", fixture.file.path, "StatCard", "Page", "--each", rows.path)

        #expect(run.status != 0)
        #expect(run.stderr.contains("gone"))
        #expect(try PenFileProbe(fixture.file).node("Page/One") == nil)
    }

    // MARK: - get

    @Test("get on a reusable component lists its parameters")
    func getListsTheParameters() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("get", fixture.file.path, "StatCard")

        #expect(run.status == 0)
        let lines = run.stdoutLines
        #expect(lines.contains { $0 == "props" })
        #expect(lines.contains { $0.contains("label") && $0.contains("Body/Title/kind.content") })
        #expect(lines.contains { $0.contains("tint") && $0.contains("Body/Swatch/kind.fills") })
        #expect(lines.contains { $0.contains("gone") && $0.contains("Body/Missing") })
    }

    @Test("get --json carries the parameters as a props array")
    func getJSONCarriesTheParameters() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("get", fixture.file.path, "StatCard", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(NodeReport.self, from: Data(run.stdout.utf8))
        let props = try #require(report.props)
        let label = try #require(props.first { $0.name == "label" })
        #expect(label.path == "Body/Title")
        #expect(label.property == "kind.content")
        #expect(label.type == .string)
        #expect(label.nodeID == "Ttl01")
        let gone = try #require(props.first { $0.name == "gone" })
        #expect(gone.nodeID == nil)
    }

    @Test("get on a node that declares no parameters prints none")
    func getPrintsNoneForAPlainComponent() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let run = try fixture.run("get", fixture.file.path, "Plain")

        #expect(run.status == 0)
        #expect(!run.stdoutLines.contains { $0 == "props" })
    }

    // MARK: - Help

    @Test("override --help and cp --help teach the parameter-name key")
    func theHelpTeachesParameterNames() throws {
        let fixture = try CommandFixture(fixture: "component-props.pen")

        let overrideHelp = try fixture.run("override", "--help")
        let copyHelp = try fixture.run("cp", "--help")

        #expect(overrideHelp.stdout.contains("_props"))
        #expect(copyHelp.stdout.contains("_props"))
    }
}
