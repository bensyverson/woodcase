//
//  RefChainAddressCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The verbs, on an instance of an *aliased* component — one whose reusable definition
/// is itself a `ref` to another component.
///
/// The expander clones the far end of that chain, so `tree --expand` prints the far
/// component's nodes. Those rows have to be addresses like any other: `get` answers
/// them, `override` writes to them, and the next `tree --expand` shows the write.
@Suite("woodcase, inside an aliased component")
struct RefChainAddressCommandTests {
    private static let penFile = "addressing-ref-chain.pen"

    // MARK: - Reading

    @Test("tree --expand prints the far component's nodes")
    func treeExpandPrintsTheFarComponent() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)

        let run = try fixture.run("tree", fixture.file.path, "Page2", "--expand", "--json")

        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(run.stdout.utf8))
        let ids = report.rows.map(\.id)
        #expect(ids.contains("Inst2/Lbl04"))
        #expect(ids.contains("Inst2/Ico04"))
    }

    @Test("get answers every id path tree --expand prints")
    func getAnswersEveryPrintedID() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)

        let listing = try fixture.run("tree", fixture.file.path, "Page2", "--expand", "--json")
        #expect(listing.status == 0, "\(listing.stderr)")
        let report = try JSONDecoder().decode(TreeReport.self, from: Data(listing.stdout.utf8))
        let inside = report.rows.filter { $0.id.contains("/") }
        #expect(!inside.isEmpty)

        for row in inside {
            let run = try fixture.run("get", fixture.file.path, row.id)
            #expect(run.status == 0, "get \(row.id) failed: \(run.stderr)")
            #expect(run.stdoutLines.first?.hasPrefix("\(row.id)  ") == true,
                    "get \(row.id) answered \(run.stdoutLines.first ?? "")")
        }
    }

    @Test("get answers the name path through the alias")
    func getAnswersTheNamePath() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)

        let run = try fixture.run("get", fixture.file.path, "Page/Primary/Stack/Icon")

        #expect(run.status == 0, "\(run.stderr)")
        #expect((run.stdoutLines.first ?? "").hasPrefix("Inst2/Ico04  Page/Primary/Stack/Icon  rev "))
    }

    // MARK: - Writing

    @Test("override lands on the far component's node and shows in the next expanded read")
    func overrideLandsAndIsVisible() throws {
        let fixture = try CommandFixture(fixture: Self.penFile)

        let write = try fixture.run(
            "override", fixture.file.path, "Inst2/Lbl04", "content=Sold", "--as", "ana"
        )
        #expect(write.status == 0, "\(write.stderr)")

        let probe = try PenFileProbe(fixture.file)
        guard case let .ref(data)? = probe.node("Page/Primary")?.kind else {
            Issue.record("Inst2 is not a ref in the written file")
            return
        }
        #expect(data.descendants?["Lbl04"]?.properties["content"] == .string("Sold"))

        let read = try fixture.run(
            "tree", fixture.file.path, "Page2", "--expand", "--props", "kind.content"
        )
        #expect(read.status == 0, "\(read.stderr)")
        #expect(read.stdout.contains("Sold"))
    }
}
