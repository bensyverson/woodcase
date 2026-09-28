//
//  NestedInstanceAddressTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The addresses `tree --expand` prints for an instance whose component nests another
/// instance below a group, driven through the binary: a read hands back addresses, and
/// every one of them has to be an address the other verbs accept.
@Suite("addresses inside a nested instance")
struct NestedInstanceAddressTests {
    /// The fixture: `Page1 > ref Card1 → CardC > group > ref Btn02 → BtnC > group > Ico02`.
    private static let penFile = "addressing-nested-instance.pen"

    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    @Test("get accepts every id-path the expanded tree prints")
    func getAcceptsEveryExpandedID() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        let tree = try fixture.run("tree", fixture.file.path, "--expand", "--json")
        #expect(tree.status == 0)

        let report = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8))
        let insideInstances = report.rows.filter { $0.id.contains("/") }
        #expect(insideInstances.count == 9)

        for row in insideInstances {
            let run = try fixture.run("get", fixture.file.path, row.id)
            #expect(run.status == 0, "get \(row.id) failed: \(run.stderr)")
            #expect(run.stdoutLines.first?.hasPrefix("\(row.id)  ") == true)
        }
    }

    @Test("set refuses a node inside the instance and names override instead")
    func setIsRefusedInsideTheInstance() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        let run = try fixture.run("set", fixture.file.path, "Card1/Btn02/Lbl02", "kind.content=Sold")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("is inside the component instance"))
        #expect(run.stderr.contains("woodcase override"))
    }

    @Test("override writes the key Pen stores for a node below a group in a nested instance")
    func overrideWritesTheNestedKey() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        let run = try fixture.run("override", fixture.file.path, "Card1/Btn02/Ico02", "fill=#00FF00")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)

        let probe = try PenFileProbe(fixture.file)
        #expect(overrides(of: probe.node("Page/Card"))["Btn02/Ico02"]?.properties["fill"]
            == .string("#00FF00"))
    }

    @Test("An overridden property shows up in the next expanded read")
    func overrideIsVisibleInTheNextRead() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)
        let write = try fixture.run("override", fixture.file.path, "Card1/Ttl03", "content=Sold")
        #expect(write.status == 0)

        let tree = try fixture.run(
            "tree", fixture.file.path, "--expand", "--json", "--props", "kind.content"
        )
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(tree.stdout.utf8))
        let title = try #require(report.rows.first { $0.id == "Card1/Ttl03" })
        #expect(title.properties?["kind.content"] == .string("Sold"))
    }
}
