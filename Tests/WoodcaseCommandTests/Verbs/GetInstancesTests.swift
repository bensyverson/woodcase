//
//  GetInstancesTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase get <definition> --instances` — every ref that draws this component.
@Suite("woodcase get --instances")
struct GetInstancesTests {
    // MARK: - The listing

    @MainActor
    @Test("Every ref targeting the definition is listed, in document order, and nothing else")
    func listsEveryInstanceInDocumentOrder() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--instances")

        #expect(run.status == 0)
        let rows = run.stdoutLines.dropFirst()
        #expect(rows.count == 3)
        #expect(rows.map { $0.split(separator: " ").map(String.init)[1] } == ["Zta01", "Alp01", "Mid01"])
        #expect(!run.stdout.contains("Oth01"))
    }

    @MainActor
    @Test("The header names the definition, its revision and how many instances there are")
    func headerNamesTheDefinition() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--instances")
        let revision = try Self.revision(of: "Cmp01", in: fixture)

        #expect(run.stdoutLines[0] == "Cmp01  Chip  rev \(revision)  3 instances")
    }

    @MainActor
    @Test("Each row carries the instance's address, id and its own revision")
    func rowsCarryAddressIDAndRevision() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--instances")
        let revision = try Self.revision(of: "Zta01", in: fixture)

        let first = try #require(run.stdoutLines.dropFirst().first)
        #expect(first.hasPrefix("Board/Zeta"))
        #expect(first.contains("Zta01"))
        #expect(first.hasSuffix("rev \(revision)"))
    }

    @Test("A definition nothing points at says so rather than printing nothing")
    func noInstancesSaysSo() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Lonely", "--instances")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdoutLines[0].hasSuffix("no instances"))
    }

    // MARK: - JSON

    @MainActor
    @Test("--json carries the definition and one object per instance with id, address and rev")
    func jsonCarriesIDAddressAndRevision() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--instances", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(InstanceReport.self, from: Data(run.stdout.utf8))
        let definitionRevision = try Self.revision(of: "Cmp01", in: fixture)
        let instanceRevision = try Self.revision(of: "Zta01", in: fixture)
        #expect(report.definition.id == "Cmp01")
        #expect(report.definition.address == "Chip")
        #expect(report.definition.rev == definitionRevision)
        #expect(report.instances.map(\.id) == ["Zta01", "Alp01", "Mid01"])
        #expect(report.instances.map(\.address) == ["Board/Zeta", "Board/Alpha", "Second/Middle"])
        #expect(report.instances.first?.rev == instanceRevision)
    }

    @Test("--json for a definition with no instances carries an empty array")
    func jsonWithNoInstances() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Lonely", "--instances", "--json")

        let report = try JSONDecoder().decode(InstanceReport.self, from: Data(run.stdout.utf8))
        #expect(report.instances.isEmpty)
    }

    // MARK: - Errors

    @Test("A node that is not reusable is a usage error naming tree as the next command")
    func nonReusableNodeIsUsage() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Board", "--instances")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Board"))
        #expect(run.stderr.contains("woodcase tree"))
    }

    @Test("--instances with --expand is refused rather than silently ignoring one of them")
    func expandAndInstancesAreRefused() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let run = try fixture.run("get", fixture.file.path, "Chip", "--instances", "--expand")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--instances"))
        #expect(run.stderr.contains("--expand"))
    }

    @Test("A read leaves the file's bytes exactly as they were")
    func readsNeverWrite() throws {
        let fixture = try CommandFixture(fixture: "instances.pen")
        let before = try Data(contentsOf: fixture.file)
        _ = try fixture.run("get", fixture.file.path, "Chip", "--instances")

        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - Helpers

    /// The revision the library computes for a node, so the test asserts against the
    /// same source of truth a later `--rev` will be checked against.
    @MainActor
    private static func revision(of nodeID: String, in fixture: CommandFixture) throws -> String {
        let parsed = try PenParser.parse(contentsOf: fixture.file)
        return try #require(EditableDocument(from: parsed).revision(of: nodeID))
    }
}
