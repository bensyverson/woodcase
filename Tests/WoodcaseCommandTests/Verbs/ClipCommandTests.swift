//
//  ClipCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase clip` — the nodes a copy takes, as a self-contained .pen on stdout.
@Suite("woodcase clip")
struct ClipCommandTests {
    @Test("The clip is printed as a .pen that carries the components it uses")
    func printsSelfContainedPen() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("clip", fixture.file.path, "BtnI")

        #expect(run.status == 0)
        let clip = try PenParser.parse(run.stdout)
        #expect(clip.children.map(\.id) == ["BtnI", "Icon", "Btn"])
        #expect(clip.variables?.keys.sorted() == ["accent", "brand"])
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("Several addresses, by name path and into an instance, come out in document order")
    func addressesByNameAndInstancePath() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")

        let run = try fixture.run("clip", fixture.file.path, "Page/Dot", "Buy/Label")

        #expect(run.status == 0)
        let clip = try PenParser.parse(run.stdout)
        #expect(clip.children.count == 2)
        guard case let .text(label)? = clip.children.first?.kind else {
            Issue.record("the instance's label did not come out first, as text")
            return
        }
        #expect(label.content == .literal("Buy"))
        #expect(clip.children.last?.id == "Free")
        #expect(clip.children.last?.common.x == .literal(105))
    }

    @Test("--json prints the clip with the ids of the roots that were copied")
    func jsonCarriesContentIDs() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")

        let run = try fixture.run("clip", fixture.file.path, "BtnI", "--json")

        #expect(run.status == 0)
        let clip = try JSONDecoder().decode(PenClip.self, from: Data(run.stdout.utf8))
        #expect(clip.contentIDs == ["BtnI"])
        #expect(clip.document.children.map(\.id) == ["BtnI", "Icon", "Btn"])
    }

    @Test("--json carries where each copied node came from")
    func jsonCarriesOrigins() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")

        let run = try fixture.run("clip", fixture.file.path, "Page/Dot", "--json")

        #expect(run.status == 0)
        let clip = try JSONDecoder().decode(PenClip.self, from: Data(run.stdout.utf8))
        #expect(clip.origins?["Free"]?.parentID == "Page")
        #expect(clip.origins?["Free"]?.offset == PenPoint(x: 5, y: 6))
    }

    @Test("Copying twice prints the same bytes")
    func deterministicBytes() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")

        let first = try fixture.run("clip", fixture.file.path, "Buy/Label", "Aliased")
        let second = try fixture.run("clip", fixture.file.path, "Buy/Label", "Aliased")

        #expect(first.status == 0)
        #expect(!first.stdout.isEmpty)
        #expect(first.stdout == second.stdout)
    }

    @Test("An address that names nothing is a usage failure that names it")
    func unknownAddress() throws {
        let fixture = try CommandFixture(fixture: "clip.pen")

        let run = try fixture.run("clip", fixture.file.path, "Nope")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nope matches no node"))
        #expect(run.stderr.contains("woodcase tree"))
        #expect(run.stdout.isEmpty)
    }
}
